import AppKit
import ChiikawaCrypto
import Foundation
import Observation
import VaultwardenAPI

/// Drives the create/edit sheet.
struct EditRequest: Identifiable {
    let id = UUID()
    let mode: EditItemSheet.Mode
}

@MainActor @Observable
final class AppModel {
    enum Phase {
        case login
        case twoFactor(providers: [String])
        /// Official cloud emailed a one-time code for this new device.
        case deviceVerification
        /// Signed in on this Mac, vault locked: unlock offline with the master password or Touch ID.
        case locked
        case vault
        var id: Int {
            switch self { case .login: 0; case .twoFactor: 1; case .deviceVerification: 3; case .locked: 4; case .vault: 2 }
        }
    }

    enum ServerKind: String, CaseIterable, Identifiable {
        case bitwardenUS, bitwardenEU, selfHosted
        var id: Self { self }
        var label: LocalizedStringResource {
            switch self {
            case .bitwardenUS: "bitwarden.com"
            case .bitwardenEU: "bitwarden.eu"
            case .selfHosted: "Self-hosted"
            }
        }
    }

    var phase: Phase = .login
    var items: [VaultItem] = []
    /// Selected item, shared by the list, detail and the Item menu commands.
    var selectedID: VaultItem.ID?
    var selectedItem: VaultItem? { items.first { $0.id == selectedID } }
    /// Non-nil while the create/edit sheet is open.
    var editing: EditRequest?
    /// True while ⌥ is held: reveals masked fields.
    var optionHeld = false
    var isOnline: Bool { client != nil && lastSynced != nil }

    /// Raw cipher JSON from the last sync, so edits can patch it without losing fields.
    private var rawCiphers: [String: Data] = [:]
    private var keyring: Keyring?
    var folders: [Grouping] = []
    /// Organizations, each with its collections as children.
    var organizations: [Grouping] = []
    var skippedOrgItems = 0
    var isBusy = false
    var errorMessage: String?

    var serverKind = ServerKind(rawValue: UserDefaults.standard.string(forKey: "serverKind") ?? "") ?? .selfHosted
    var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "https://"
    var email = UserDefaults.standard.string(forKey: "email") ?? ""

    var isUnlocked: Bool { phase.id == Phase.vault.id }

    /// Last successful sync with the server; nil while showing cached data only.
    var lastSynced: Date?
    var isSyncing = false
    var touchIDEnabled = AccountStore.isTouchIDEnabled

    init() {
        if let saved = AccountStore.load() {
            serverKind = ServerKind(rawValue: saved.serverKind) ?? .selfHosted
            serverURL = saved.serverURL
            email = saved.email
            phase = .locked
        }
    }

    enum ServerStatus: Equatable {
        case unknown, checking
        case reachable(product: String, version: String?)
        case unreachable(String)
    }
    var serverStatus: ServerStatus = .unknown
    private var statusTask: Task<Void, Never>?

    /// Bumped each time Quick Search opens, so the panel resets and focuses.
    var quickSearchNonce = 0

    /// Transient confirmation shown after copying.
    var toast: String?
    private var toastTask: Task<Void, Never>?
    private var clearTask: Task<Void, Never>?

    private var client: VaultClient?
    private var userKey: SymmetricKeyPair?

    private var deviceIdentifier: String {
        if let id = UserDefaults.standard.string(forKey: "deviceIdentifier") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "deviceIdentifier")
        return id
    }

    /// A client for `environment` with the user's extra headers and trusted CAs applied.
    private func makeClient(_ environment: ServerEnvironment) -> VaultClient {
        let session = makeSession()
        return VaultClient(environment: environment, deviceIdentifier: deviceIdentifier,
                           extraHeaders: HeaderStore.dictionary, session: session)
    }

    private func makeSession() -> URLSession {
        let cas = UserDefaults.standard.array(forKey: Pref.trustedCAs) as? [Data] ?? []
        return cas.isEmpty ? URLSession.shared : ServerTrust(certificates: cas).makeSession()
    }

    // MARK: Live sync

    private var live: LiveSync?
    private var liveDebounce: Task<Void, Never>?
    private var periodicSync: Timer?

    /// Connects to the notifications hub so changes on other devices appear within a second or two.
    private func startLiveSync() async {
        guard live == nil, let client, let token = await client.currentAccessToken else { return }
        let live = LiveSync(environment: client.environment, accessToken: token, session: makeSession()) { [weak self] in
            Task { @MainActor in self?.scheduleSync() }
        }
        self.live = live
        do { try await live.start() } catch { self.live = nil }
        if periodicSync == nil {
            periodicSync = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleSync() }
            }
        }
    }

    private func stopLiveSync() {
        let live = self.live
        self.live = nil
        Task { await live?.stop() }
        periodicSync?.invalidate()
        periodicSync = nil
    }

    /// Coalesces bursts of change notifications into one sync.
    func scheduleSync() {
        guard isUnlocked else { return }
        liveDebounce?.cancel()
        liveDebounce = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            do { try await refresh() } catch {
                // Token likely expired: refresh it once and retry.
                if let token = try? await client?.refreshAccessToken() { AccountStore.refreshToken = token }
                try? await refresh()
            }
        }
    }

    /// Re-sync when the app comes to the front if the last sync is stale.
    func appDidBecomeActive() {
        // AutoFill may have just been switched on in System Settings.
        if isUnlocked { AutoFillIdentities.publish(items) }
        if isUnlocked, (lastSynced.map { Date.now.timeIntervalSince($0) > 60 } ?? true) { scheduleSync() }
    }

    /// Drop the cached client so new headers / certificates take effect on the next request.
    func resetClient() {
        if !isUnlocked { client = nil }
        checkServer()
    }

    var serverSummary: String {
        switch serverKind {
        case .bitwardenUS: "bitwarden.com"
        case .bitwardenEU: "bitwarden.eu"
        case .selfHosted: serverURL
        }
    }

    /// Sign out on this Mac: forget the session, cached vault and Touch ID.
    func logOut() {
        stopLiveSync()
        AutoFillIdentities.clear()
        AccountStore.erase()
        touchIDEnabled = false
        userKey = nil
        items = []
        client = nil
        lastSynced = nil
        email = ""
        UserDefaults.standard.removeObject(forKey: "email")
        phase = .login
    }

    private func environment() -> ServerEnvironment? {
        switch serverKind {
        case .bitwardenUS: return .bitwardenUS
        case .bitwardenEU: return .bitwardenEU
        case .selfHosted:
            guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)), url.host() != nil else { return nil }
            return .selfHosted(url)
        }
    }

    /// Pings the selected server's public `/api/config`, debounced while the user types a URL.
    func checkServer() {
        statusTask?.cancel()
        guard let environment = environment() else { serverStatus = .unknown; return }
        serverStatus = .checking
        statusTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let probe = makeClient(environment)
            do {
                let config = try await probe.config()
                guard !Task.isCancelled else { return }
                serverStatus = .reachable(product: config.productName, version: config.version)
            } catch {
                guard !Task.isCancelled else { return }
                serverStatus = .unreachable(String(localized: "Can't reach this server"))
            }
        }
    }

    enum HintResult { case success(String?), failure(String) }

    func requestPasswordHint(email: String) async -> HintResult {
        guard let environment = environment() else { return .failure(String(localized: "Enter a valid server URL.")) }
        do {
            let hint = try await makeClient(environment).requestPasswordHint(email: email)
            return .success(hint)
        } catch {
            if case .http(_, let message?) = error as? APIError { return .failure(message) }
            return .failure(String(localized: "Couldn't send the hint. Check the server and try again."))
        }
    }

    /// Copies a secret, hides it from clipboard managers, and clears it after the configured delay if unchanged.
    func copy(_ value: String, label: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let change = pb.changeCount
        let seconds = UserDefaults.standard.integer(forKey: Pref.clipboardSeconds)
        clearTask?.cancel()
        if seconds > 0 {
            clearTask = Task {
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled, pb.changeCount == change { pb.clearContents() }
            }
            toast = String(localized: "\(label) copied · clears in \(seconds) s")
        } else {
            toast = String(localized: "\(label) copied")
        }
        noteActivity()
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            if !Task.isCancelled { toast = nil }
        }
    }

    /// - Parameters:
    ///   - code: the authenticator code in `.twoFactor`, or the emailed code in `.deviceVerification`.
    func login(password: String, code: String? = nil) async {
        guard let environment = environment() else {
            errorMessage = String(localized: "Enter a valid server URL.")
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let client = self.client?.environment == environment ? self.client! : makeClient(environment)
        self.client = client
        let isDeviceCode: Bool = if case .deviceVerification = phase { true } else { false }
        do {
            // Provider "0" is the authenticator app (TOTP).
            let result = try await client.loginDetailed(email: email, password: password,
                                                        twoFactor: isDeviceCode ? nil : code.map { ("0", $0) },
                                                        newDeviceOTP: isDeviceCode ? code : nil)
            UserDefaults.standard.set(serverKind.rawValue, forKey: "serverKind")
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            UserDefaults.standard.set(email, forKey: "email")
            AccountStore.save(SavedAccount(email: email, serverKind: serverKind.rawValue, serverURL: serverURL,
                                           kdf: result.kdf, protectedUserKey: result.protectedUserKey))
            AccountStore.refreshToken = result.refreshToken
            userKey = result.userKey
            try await refresh()
            phase = .vault
        } catch {
            handle(error)
        }
    }

    /// Pulls the vault from the server, caches the (still encrypted) payload, and rebuilds the list.
    func refresh() async throws {
        guard let client, userKey != nil else { return }
        isSyncing = true
        defer { isSyncing = false }
        let data = try await client.syncData()
        AccountStore.saveCache(data)
        try load(cache: data)
        lastSynced = .now
        await startLiveSync()
    }

    // MARK: Unlock

    /// Offline unlock: re-derive the master key locally; the MAC on the protected key proves the password.
    func unlock(password: String) async {
        guard let saved = AccountStore.load() else { phase = .login; return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        _ = saved
        let derived = await Task.detached(priority: .userInitiated) { AccountStore.unlock(password: password) }.value
        guard let derived else {
            errorMessage = String(localized: "Wrong master password.")
            return
        }
        finishUnlock(with: derived)
    }

    func unlockWithTouchID() async {
        errorMessage = nil
        let reason = String(localized: "unlock your vault")
        let key = await Task.detached { try? AccountStore.unlockWithTouchID(reason: reason) }.value
        if let key { finishUnlock(with: key) }
    }

    private func finishUnlock(with key: SymmetricKeyPair) {
        userKey = key
        if let cache = AccountStore.loadCache() { try? load(cache: cache) }
        phase = .vault
        noteActivity()
        Task { await resumeSession() }
    }

    /// Reconnects in the background with the stored refresh token, then syncs. Failures keep the cached vault.
    private func resumeSession() async {
        guard let environment = environment(), let token = AccountStore.refreshToken else { return }
        let client = self.client ?? makeClient(environment)
        self.client = client
        do {
            await client.restore(refreshToken: token)
            AccountStore.refreshToken = try await client.refreshAccessToken()
            try await refresh()
        } catch {
            // Offline or session expired: keep showing the cache; the sidebar shows the sync state.
        }
    }

    func setTouchID(_ enabled: Bool) {
        if enabled, let userKey {
            do { try AccountStore.enableTouchID(userKey: userKey); touchIDEnabled = true } catch {
                toast = String(localized: "Couldn't turn on Touch ID")
                touchIDEnabled = false
            }
        } else if !enabled {
            AccountStore.disableTouchID()
            touchIDEnabled = false
        }
    }

    private func load(cache data: Data) throws {
        guard let userKey else { return }
        let vault = try VaultDecoder.decode(data, userKey: userKey)
        items = vault.items
        folders = vault.folders
        organizations = vault.organizations
        skippedOrgItems = vault.hiddenCount
        keyring = vault.keyring
        rawCiphers = vault.rawCiphers
        AutoFillIdentities.publish(vault.items)
    }

    // MARK: Editing

    enum NewItemKind { case login, secureNote }

    @discardableResult
    func createItem(_ kind: NewItemKind, edit: CipherEdit) async -> Bool {
        guard let client, let key = userKey else { return offline() }
        do {
            let body = try CipherEditor.newCipher(kind: kind == .login ? .login : .secureNote, edit: edit, key: key)
            let id = try await client.createCipher(body)
            try await refresh()
            selectedID = id
            flash(String(localized: "Item created"))
            return true
        } catch { return failed(error) }
    }

    @discardableResult
    func updateItem(_ id: String, edit: CipherEdit) async -> Bool {
        guard let client, let raw = rawCiphers[id], let cipher = try? SyncResponse.decode(cacheData()).ciphers.first(where: { $0.id == id }),
              let key = keyring?.key(for: cipher) else { return offline() }
        do {
            try await client.updateCipher(id: id, CipherEditor.updatedCipher(raw: raw, edit: edit, key: key))
            try await refresh()
            return true
        } catch { return failed(error) }
    }

    func toggleFavorite(_ item: VaultItem) async {
        await updateItem(item.id, edit: CipherEdit(favorite: !item.favorite))
    }

    func trash(_ item: VaultItem) async {
        guard let client else { _ = offline(); return }
        do {
            try await client.trashCipher(id: item.id)
            try await refresh()
            flash(String(localized: "Moved to Trash"))
        } catch { _ = failed(error) }
    }

    func restore(_ item: VaultItem) async {
        guard let client else { _ = offline(); return }
        do {
            try await client.restoreCipher(id: item.id)
            try await refresh()
            flash(String(localized: "Restored"))
        } catch { _ = failed(error) }
    }

    func deleteForever(_ item: VaultItem) async {
        guard let client else { _ = offline(); return }
        do {
            try await client.deleteCipher(id: item.id)
            if selectedID == item.id { selectedID = nil }
            try await refresh()
            flash(String(localized: "Deleted permanently"))
        } catch { _ = failed(error) }
    }

    private func cacheData() -> Data { AccountStore.loadCache() ?? Data() }

    private func offline() -> Bool {
        flash(String(localized: "You're offline — changes need a connection to your server."))
        return false
    }

    private func failed(_ error: Error) -> Bool {
        if case .http(let status, let message)? = error as? APIError {
            flash(message ?? String(localized: "Server error (\(status))."))
        } else {
            flash(error.localizedDescription)
        }
        return false
    }

    func flash(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { toast = nil }
        }
    }

    // MARK: Auto-lock

    private var lastActivity = Date()
    private var monitors: [Any] = []
    private var autoLockTimer: Timer?

    func noteActivity() { lastActivity = .now }

    /// Locks after inactivity and on sleep / screen lock, per Settings.
    func startAutoLock() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .scrollWheel, .mouseMoved], handler: { [weak self] e in
            self?.noteActivity(); return e
        }) { monitors.append(m) }
        // Hold ⌥ to reveal masked fields (only ⌥, so ⌥-shortcuts don't flash secrets).
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            self?.optionHeld = flags == .option
            return e
        }) { monitors.append(m) }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            monitors.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockIfConfiguredOnSleep() }
            })
        }
        monitors.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockIfConfiguredOnSleep() }
        })
        autoLockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isUnlocked else { return }
                let minutes = UserDefaults.standard.integer(forKey: Pref.autoLockMinutes)
                if minutes > 0, Date.now.timeIntervalSince(self.lastActivity) > Double(minutes) * 60 { self.lock() }
            }
        }
    }

    private func lockIfConfiguredOnSleep() {
        if isUnlocked, UserDefaults.standard.bool(forKey: Pref.lockOnSleep) { lock() }
    }

    func lock() {
        stopLiveSync()
        rawCiphers = [:]
        keyring = nil
        selectedID = nil
        userKey = nil
        items = []
        folders = []
        organizations = []
        phase = AccountStore.load() != nil ? .locked : .login
    }

    func cancelChallenge() {
        errorMessage = nil
        phase = .login
    }

    var serverDisplayName: String { client?.environment.displayHost ?? "" }

    private func handle(_ error: Error) {
        switch error as? APIError {
        case .twoFactorRequired(let providers)?:
            phase = .twoFactor(providers: providers)
        case .newDeviceVerificationRequired?:
            phase = .deviceVerification
        case .captchaRequired?:
            errorMessage = String(localized: "Bitwarden asked for a captcha. Log in once at vault.bitwarden.com from this network, then try again.")
        case .crypto(.unsupported)?:
            errorMessage = String(localized: "This account uses Argon2id, which isn't supported yet.")
        case .crypto(.kdfOutOfBounds)?:
            errorMessage = String(localized: "The server sent unsafe key-derivation settings. Login was stopped.")
        case .crypto?:
            errorMessage = String(localized: "Wrong email or master password.")
        case .http(let status, let message)?:
            errorMessage = message ?? String(localized: "Server error (\(status)).")
        default:
            errorMessage = error.localizedDescription
        }
    }
}
