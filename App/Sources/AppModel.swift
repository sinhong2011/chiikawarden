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
    /// Every account saved on this Mac, oldest first.
    private(set) var accounts: [SavedAccount] = AccountStore.accounts()
    /// Unlocked accounts. Items from all of them are merged into `items`.
    private(set) var sessions: [AccountSession] = []
    /// The account the unlock screen is asking for.
    var unlockTargetID: String?
    var unlockTarget: SavedAccount? { accounts.first { $0.id == unlockTargetID } ?? accounts.first }
    /// Sidebar filter: show one account only.
    var accountFilter: String?
    /// True while adding another account from an unlocked vault (login screen can be cancelled).
    var addingAccount = false
    var items: [VaultItem] = []
    /// Selected item, shared by the list, detail and the Item menu commands.
    var selectedID: VaultItem.ID?
    var selectedItem: VaultItem? { items.first { $0.id == selectedID } }
    /// Non-nil while the create/edit sheet is open.
    var editing: EditRequest?
    /// True while ⌥ is held: reveals masked fields.
    var optionHeld = false
    var isOnline: Bool { sessions.contains { $0.lastSynced != nil } }
    var folders: [Grouping] = []
    /// Organizations, each with its collections as children.
    var organizations: [Grouping] = []
    var skippedOrgItems = 0
    var isBusy = false
    var errorMessage: String?

    var serverKind = ServerKind(rawValue: UserDefaults.standard.string(forKey: "serverKind") ?? "") ?? .selfHosted
    var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "https://"
    var email = UserDefaults.standard.string(forKey: "email") ?? ""

    var isUnlocked: Bool { phase.id == Phase.vault.id && !sessions.isEmpty }

    /// Most recent successful sync across accounts; nil while showing cached data only.
    var lastSynced: Date? { sessions.compactMap(\.lastSynced).max() }
    var isSyncing: Bool { sessions.contains(where: \.isSyncing) }
    /// Whether any locked account can be opened with Touch ID (unlock screen).
    var touchIDEnabled = false

    init() {
        IconStore.shared.makeSession = { [weak self] in self?.makeSession() ?? .shared }
        refreshAccounts()
        if !accounts.isEmpty { phase = .locked }
    }

    private func refreshAccounts() {
        accounts = AccountStore.accounts()
        if unlockTargetID == nil || !accounts.contains(where: { $0.id == unlockTargetID }) {
            unlockTargetID = accounts.first { a in !sessions.contains { $0.id == a.id } }?.id ?? accounts.first?.id
        }
        touchIDEnabled = accounts.contains { a in AccountStore.isTouchIDEnabled(a.id) && !sessions.contains { $0.id == a.id } }
    }

    func session(for accountId: String) -> AccountSession? { sessions.first { $0.id == accountId } }

    // MARK: Watchtower

    /// Item id → times seen in breaches; nil until the user runs a check.
    var breachCounts: [String: Int]?
    var breachesCheckedAt: Date?
    var isCheckingBreaches = false

    func checkBreaches() async {
        isCheckingBreaches = true
        defer { isCheckingBreaches = false }
        let logins = items.filter { !$0.isDeleted && $0.password != nil }
        do {
            let counts = try await PwnedPasswords.check(Set(logins.compactMap(\.password)), session: makeSession())
            breachCounts = Dictionary(logins.map { ($0.id, counts[$0.password!] ?? 0) }, uniquingKeysWith: { a, _ in a })
            breachesCheckedAt = .now
        } catch {
            flash(String(localized: "Couldn't reach Have I Been Pwned. Try again later."))
        }
    }

    /// Logins with any locally-detectable issue (sidebar badge).
    var watchtowerIssueCount: Int { WatchtowerReport(items: items, breaches: breachCounts).problemCount }

    #if DEBUG
    /// Snapshot/demo only: pretend these accounts are saved.
    func setPreviewAccounts(_ accounts: [SavedAccount]) { self.accounts = accounts; unlockTargetID = accounts.first?.id }
    #endif
    func isUnlocked(_ accountId: String) -> Bool { session(for: accountId) != nil }
    func isTouchIDEnabled(_ accountId: String) -> Bool { AccountStore.isTouchIDEnabled(accountId) }

    /// Merges every unlocked account into one list.
    private func rebuild() {
        let multi = sessions.count > 1
        items = sessions.flatMap(\.items).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        folders = sessions.flatMap(\.folders)
        organizations = sessions.flatMap(\.organizations)
        skippedOrgItems = sessions.reduce(0) { $0 + $1.hiddenCount }
        if !multi { accountFilter = nil }
        if let id = selectedID, !items.contains(where: { $0.id == id }) { selectedID = nil }
        AutoFillIdentities.publish(items)
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

    /// Login-in-progress client (kept between the password and 2FA steps).
    private var client: VaultClient?

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

    func scheduleSync() {
        guard isUnlocked else { return }
        sessions.forEach { $0.scheduleSync() }
    }

    /// Re-sync when the app comes to the front if the last sync is stale.
    func appDidBecomeActive() {
        // AutoFill may have just been switched on in System Settings.
        if isUnlocked { AutoFillIdentities.publish(items) }
        for session in sessions where session.lastSynced.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true {
            session.scheduleSync()
        }
    }

    /// Drop the cached client so new headers / certificates take effect on the next request.
    func resetClient() {
        client = nil
        checkServer()
    }

    var serverSummary: String {
        switch serverKind {
        case .bitwardenUS: "bitwarden.com"
        case .bitwardenEU: "bitwarden.eu"
        case .selfHosted: serverURL
        }
    }

    /// Sign one account out on this Mac: forget its session, cached vault, token and Touch ID.
    /// With no id: the account the unlock screen shows.
    func logOut(_ accountId: String? = nil) {
        guard let id = accountId ?? unlockTarget?.id else { return }
        if let session = session(for: id) { session.close() }
        sessions.removeAll { $0.id == id }
        AccountStore.erase(id)
        if accountFilter == id { accountFilter = nil }
        unlockTargetID = nil
        refreshAccounts()
        rebuild()
        if accounts.isEmpty {
            AutoFillIdentities.clear()
            email = ""
            UserDefaults.standard.removeObject(forKey: "email")
            phase = .login
        } else if sessions.isEmpty {
            phase = .locked
        }
    }

    /// Opens the login screen to add another account (cancellable back to the vault).
    func beginAddAccount() {
        addingAccount = true
        client = nil
        errorMessage = nil
        email = ""
        serverURL = "https://"
        phase = .login
    }

    func cancelAddAccount() {
        addingAccount = false
        errorMessage = nil
        phase = sessions.isEmpty ? (accounts.isEmpty ? .login : .locked) : .vault
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
            let id = SavedAccount.makeID(serverKind: serverKind.rawValue, serverURL: serverURL, email: email)
            let account = SavedAccount(id: id, email: email, serverKind: serverKind.rawValue, serverURL: serverURL,
                                       kdf: result.kdf, protectedUserKey: result.protectedUserKey)
            AccountStore.save(account)
            AccountStore.setRefreshToken(result.refreshToken, id)
            let session = open(account, key: result.userKey, client: client)
            self.client = nil
            try await session.refresh()
            addingAccount = false
            phase = .vault
        } catch {
            handle(error)
        }
    }

    /// Syncs every unlocked account now.
    func refresh() async throws {
        for session in sessions { try await session.refresh() }
    }

    // MARK: Unlock

    @discardableResult
    private func open(_ account: SavedAccount, key: SymmetricKeyPair, client: VaultClient? = nil) -> AccountSession {
        if let existing = session(for: account.id) { existing.close() }
        sessions.removeAll { $0.id == account.id }
        let session = AccountSession(account: account, userKey: key, client: client,
                                     makeClient: { [weak self] env in self?.makeClient(env) ?? VaultClient(environment: env, deviceIdentifier: "") },
                                     makeSession: { [weak self] in self?.makeSession() ?? .shared })
        session.onChange = { [weak self] in self?.rebuild() }
        sessions.append(session)
        sessions.sort { a, b in
            (accounts.firstIndex { $0.id == a.id } ?? 0) < (accounts.firstIndex { $0.id == b.id } ?? 0)
        }
        refreshAccounts()
        rebuild()
        return session
    }

    /// Offline unlock of one account (the unlock screen's target, or `accountId`).
    func unlock(password: String, accountId: String? = nil) async {
        guard let target = accountId.flatMap({ id in accounts.first { $0.id == id } }) ?? unlockTarget else { phase = .login; return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let id = target.id
        let derived = await Task.detached(priority: .userInitiated) { AccountStore.unlock(id, password: password) }.value
        guard let derived else {
            errorMessage = String(localized: "Wrong master password.")
            return
        }
        finishUnlock([target.id: derived])
    }

    /// One Touch ID prompt unlocks every locked account that has it turned on.
    func unlockWithTouchID() async {
        errorMessage = nil
        let locked = accounts.map(\.id).filter { !isUnlocked($0) }
        let keys = await AccountStore.unlockAllWithTouchID(locked, reason: String(localized: "unlock your vault"))
        if !keys.isEmpty { finishUnlock(keys) }
    }

    private func finishUnlock(_ keys: [String: SymmetricKeyPair]) {
        for (id, key) in keys {
            guard let account = accounts.first(where: { $0.id == id }) else { continue }
            let session = open(account, key: key)
            Task { await session.resume() }
        }
        phase = .vault
        noteActivity()
    }

    func setTouchID(_ enabled: Bool, for accountId: String) {
        guard let session = session(for: accountId) else { return }
        do { try session.setTouchID(enabled) } catch { flash(String(localized: "Couldn't turn on Touch ID")) }
        refreshAccounts()
    }

    /// Locks one account; the others stay open.
    func lock(_ accountId: String) {
        session(for: accountId)?.close()
        sessions.removeAll { $0.id == accountId }
        if accountFilter == accountId { accountFilter = nil }
        refreshAccounts()
        rebuild()
        if sessions.isEmpty { lock() }
    }

    // MARK: Editing

    enum NewItemKind { case login, secureNote }

    /// Where new items go: the filtered account, else the first unlocked one.
    var defaultAccountId: String? { accountFilter ?? sessions.first?.id }

    @discardableResult
    func createItem(_ kind: NewItemKind, edit: CipherEdit, accountId: String? = nil) async -> Bool {
        guard let session = (accountId ?? defaultAccountId).flatMap(session(for:)) else { return offline() }
        do {
            let id = try await session.create(kind == .login ? .login : .secureNote, edit: edit)
            selectedID = id
            flash(String(localized: "Item created"))
            return true
        } catch { return failed(error) }
    }

    private func session(for item: VaultItem) -> AccountSession? {
        session(for: item.accountId) ?? sessions.first { s in s.items.contains { $0.id == item.id } }
    }

    @discardableResult
    func updateItem(_ id: String, edit: CipherEdit) async -> Bool {
        guard let item = items.first(where: { $0.id == id }), let session = session(for: item) else { return offline() }
        do {
            try await session.update(id, edit: edit)
            return true
        } catch { return failed(error) }
    }

    func toggleFavorite(_ item: VaultItem) async {
        await updateItem(item.id, edit: CipherEdit(favorite: !item.favorite))
    }

    func trash(_ item: VaultItem) async {
        guard let session = session(for: item) else { _ = offline(); return }
        do {
            try await session.trash(item.id)
            flash(String(localized: "Moved to Trash"))
        } catch { _ = failed(error) }
    }

    func restore(_ item: VaultItem) async {
        guard let session = session(for: item) else { _ = offline(); return }
        do {
            try await session.restore(item.id)
            flash(String(localized: "Restored"))
        } catch { _ = failed(error) }
    }

    func deleteForever(_ item: VaultItem) async {
        guard let session = session(for: item) else { _ = offline(); return }
        do {
            try await session.deleteForever(item.id)
            if selectedID == item.id { selectedID = nil }
            flash(String(localized: "Deleted permanently"))
        } catch { _ = failed(error) }
    }

    private func offline() -> Bool {
        flash(String(localized: "You're offline — changes need a connection to your server."))
        return false
    }

    private func failed(_ error: Error) -> Bool {
        if error is AccountSession.WriteError { return offline() }
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

    /// Locks every account.
    func lock() {
        breachCounts = nil
        breachesCheckedAt = nil
        sessions.forEach { $0.close() }
        sessions = []
        selectedID = nil
        accountFilter = nil
        items = []
        folders = []
        organizations = []
        refreshAccounts()
        addingAccount = false
        phase = accounts.isEmpty ? .login : .locked
    }

    func cancelChallenge() {
        errorMessage = nil
        phase = .login
    }

    var serverDisplayName: String {
        sessions.count > 1 ? String(localized: "\(sessions.count) accounts") : (sessions.first?.account.serverSummary ?? "")
    }

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
