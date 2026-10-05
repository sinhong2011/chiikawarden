import AppKit
import ChiikawaCrypto
import LocalAuthentication
import Foundation
import Observation
import SwiftUI
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
        /// Single sign-on succeeded; the master password still has to decrypt the vault.
        case ssoPassword
        /// Signed in on this Mac, vault locked: unlock offline with the master password or Touch ID.
        case locked
        case vault
        var id: Int {
            switch self { case .login: 0; case .twoFactor: 1; case .deviceVerification: 3; case .ssoPassword: 5; case .locked: 4; case .vault: 2 }
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
    /// True while the New Folder prompt is showing.
    var promptingNewFolder = false
    /// Non-nil while the create/edit sheet is open.
    var editing: EditRequest?
    /// The import or export sheet; an import may start with a file (dropped on the window).
    var transfer: Transfer?

    enum Transfer: Identifiable {
        case export
        case importFile(URL?)
        var id: String {
            switch self { case .export: "export"; case .importFile(let url): "import-" + (url?.path ?? "") }
        }
    }

    func beginExport() { bringToFront(); transfer = .export }
    func beginImport(_ url: URL? = nil) { bringToFront(); transfer = .importFile(url) }

    /// Checks a master password offline (re-entry before an export).
    func verifyMasterPassword(_ password: String, accountId: String) -> Bool {
        AccountStore.unlock(accountId, password: password) != nil
    }
    /// True while ⌥ is held: reveals masked fields.
    var optionHeld = false
    var isOnline: Bool { sessions.contains { $0.lastSynced != nil } }
    var folders: [Grouping] = []
    var sends: [SendItem] = []
    var selectedSendID: SendItem.ID?
    var composingSend = false
    /// Organizations, each with its collections as children.
    var organizations: [Grouping] = []
    var skippedOrgItems = 0
    var isBusy = false
    var errorMessage: String?

    var serverKind = ServerKind(rawValue: UserDefaults.standard.string(forKey: "serverKind") ?? "") ?? .selfHosted
    var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "https://"
    var email = UserDefaults.standard.string(forKey: "email") ?? ""
    /// Optional "Custom environment" fields for self-hosted servers (empty = derive from the server URL).
    var customWebVault = ""
    var customAPI = ""
    var customIdentity = ""
    var customIcons = ""
    var customNotifications = ""
    var hasCustomURLs: Bool {
        ![customWebVault, customAPI, customIdentity, customIcons, customNotifications]
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var isUnlocked: Bool { phase.id == Phase.vault.id && (!sessions.isEmpty || previewUnlocked) }
    /// Snapshots and `--demo`: treat demo items as an unlocked vault.
    var previewUnlocked = false

    /// Most recent successful sync across accounts; nil while showing cached data only.
    var lastSynced: Date? { sessions.compactMap(\.lastSynced).max() }
    var isSyncing: Bool { sessions.contains(where: \.isSyncing) }
    /// Whether any locked account can be opened with Touch ID (unlock screen).
    var touchIDEnabled = false

    /// Serves SSH key items to ssh/git while unlocked (Settings › SSH).
    @ObservationIgnored private(set) var sshAgent: SSHAgentService!
    @ObservationIgnored private(set) var cli: CLIBridge!
    let updates: Updater

    /// The app's live model, for App Intents and the CLI bridge.
    nonisolated(unsafe) static weak var current: AppModel?

    init() {
        // No updater while testing, rendering snapshots, previewing or showing the demo vault.
        let quiet = CommandLine.arguments.contains { ["--selftest", "--snapshot", "--demo"].contains($0) || $0.hasPrefix("--selftest") }
            || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        updates = Updater(start: !quiet)
        AttachmentFiles.wipe() // leftovers from a crash
        Self.current = self
        sshAgent = SSHAgentService(model: self)
        let tooling = CommandLine.arguments.contains { $0 == "--selftest" || $0 == "--snapshot" }
            || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" // Xcode canvas
        if !tooling, UserDefaults.standard.bool(forKey: Pref.sshAgent) { sshAgent.start() }
        cli = CLIBridge(model: self)
        if !tooling { cli.refreshRunning() }
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
    /// Previews, snapshots and `--demo`: in-memory accounts, no Touch ID (it would prompt for real).
    func setPreviewAccounts(_ accounts: [SavedAccount]) {
        self.accounts = accounts
        unlockTargetID = accounts.first?.id
        touchIDEnabled = false
    }
    #endif
    func isUnlocked(_ accountId: String) -> Bool { session(for: accountId) != nil }
    func isTouchIDEnabled(_ accountId: String) -> Bool { AccountStore.isTouchIDEnabled(accountId) }

    /// Merges every unlocked account into one list.
    private func rebuild() {
        let multi = sessions.count > 1
        items = sessions.flatMap(\.items).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        folders = sessions.flatMap(\.folders)
        organizations = sessions.flatMap(\.organizations)
        sends = sessions.flatMap(\.sends)
        if let id = selectedSendID, !sends.contains(where: { $0.id == id }) { selectedSendID = nil }
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
    /// Opens the command palette (set by the app; the search box, ⌘K/⌘F and the global shortcut all use it).
    @ObservationIgnored var openPalette: () -> Void = {}
    /// SwiftUI's `openSettings`, captured by the main window (it only exists inside a scene).
    @ObservationIgnored var openSettingsAction: () -> Void = {}

    /// Brings the app forward and opens Settings (from the menu bar, the palette, the account menu).
    func showSettings() {
        NSApp.activate()
        openSettingsAction()
    }
    /// Sidebar destination asked for from outside the vault view (palette commands).
    var requestedSection: SidebarSelection?
    var showingGenerator = false

    /// A destructive action waiting for “Are you sure?” (one dialog for the whole app).
    struct ConfirmRequest: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let action: String
        let run: @MainActor () async -> Void
    }
    var confirming: ConfirmRequest?

    func confirm(_ title: String, message: String, action: String, run: @escaping @MainActor () async -> Void) {
        confirming = ConfirmRequest(title: title, message: message, action: action, run: run)
    }

    /// Asks, then moves the item to Trash.
    func confirmTrash(_ item: VaultItem) {
        confirm(String(localized: "Move “\(item.name)” to Trash?"), message: String(localized: "You can restore it from Trash later."),
                action: String(localized: "Move to Trash")) { [weak self] in await self?.trash(item) }
    }

    /// Asks, then logs the account out (removing it from this Mac).
    func confirmLogOut(_ accountId: String?) {
        let email = accountId.flatMap { id in accounts.first { $0.id == id }?.email } ?? ""
        confirm(String(localized: "Log out of \(email)?"),
                message: String(localized: "The account and its saved vault are removed from this Mac. Your vault stays on the server."),
                action: String(localized: "Log Out")) { [weak self] in self?.logOut(accountId) }
    }

    /// Generated values the user copied or used, newest first. Memory only; cleared on lock.
    struct GeneratedEntry: Identifiable { let id = UUID(); let value: String; let kind: String; let date: Date }
    var generatorHistory: [GeneratedEntry] = []

    func rememberGenerated(_ value: String, kind: String) {
        guard !value.isEmpty, generatorHistory.first?.value != value else { return }
        generatorHistory.insert(GeneratedEntry(value: value, kind: kind, date: .now), at: 0)
        if generatorHistory.count > 50 { generatorHistory.removeLast() }
    }

    /// Shows the main window, e.g. after a palette command run from another app.
    func bringToFront() {
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    /// Selects an item in the vault list.
    func showItem(_ id: String) {
        bringToFront()
        requestedSection = .section(.all)
        selectedID = id
    }

    /// Transient confirmation shown after copying.
    var toast: String?
    private var toastTask: Task<Void, Never>?
    private var clearTask: Task<Void, Never>?

    /// Login-in-progress client (kept between the password and 2FA steps).
    private var client: VaultClient?

    private func makeClient(_ environment: ServerEnvironment) -> VaultClient { Connection.makeClient(environment) }
    private func makeSession() -> URLSession { Connection.makeSession() }

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
        (customWebVault, customAPI, customIdentity, customIcons, customNotifications) = ("", "", "", "", "")
        phase = .login
    }

    func cancelAddAccount() {
        addingAccount = false
        errorMessage = nil
        phase = sessions.isEmpty ? (accounts.isEmpty ? .login : .locked) : .vault
    }

    /// Why the self-hosted URLs can't be used, or nil when they're fine.
    var serverURLProblem: String? {
        guard serverKind == .selfHosted else { return nil }
        let fields = [serverURL, customWebVault, customAPI, customIdentity, customIcons, customNotifications]
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "https://" && $0 != "http://" }
        for text in fields {
            guard let url = Self.parseURL(text) else { return String(localized: "“\(text)” isn't a valid URL.") }
            if url.scheme == "http", WatchtowerReport.isInsecure(url.absoluteString) {
                return String(localized: "Use https:// for servers on the internet. http:// is only allowed on your local network.")
            }
        }
        return nil
    }

    /// Accepts "vault.example.com" (adds https://) and trims trailing slashes, like the official clients.
    static func parseURL(_ text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespaces)
        while t.hasSuffix("/") { t.removeLast() }
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard let url = URL(string: t), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil else { return nil }
        return url
    }

    private var customURLs: CustomURLs? {
        guard hasCustomURLs else { return nil }
        let urls = CustomURLs(base: Self.parseURL(serverURL), webVault: Self.parseURL(customWebVault), api: Self.parseURL(customAPI),
                              identity: Self.parseURL(customIdentity), icons: Self.parseURL(customIcons),
                              notifications: Self.parseURL(customNotifications))
        return urls.isUsable ? urls : nil
    }

    private func environment() -> ServerEnvironment? {
        switch serverKind {
        case .bitwardenUS: return .bitwardenUS
        case .bitwardenEU: return .bitwardenEU
        case .selfHosted:
            guard serverURLProblem == nil else { return nil }
            if hasCustomURLs { return customURLs.map(ServerEnvironment.custom) }
            return Self.parseURL(serverURL).map(ServerEnvironment.selfHosted)
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
    /// Copies non-secret text (config snippets, public keys) without the clipboard timer.
    func copyPlain(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        flash(String(localized: "Copied"))
    }

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
            errorMessage = serverURLProblem ?? String(localized: "Enter a valid server URL.")
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
            try await finishLogin(environment: environment, client: client, kdf: result.kdf, protectedUserKey: result.protectedUserKey,
                                  userKey: result.userKey, refreshToken: result.refreshToken)
        } catch {
            handle(error)
        }
    }

    /// Saves the account, opens its session and syncs — shared by password and SSO login.
    private func finishLogin(environment: ServerEnvironment, client: VaultClient, kdf: KDFConfig, protectedUserKey: String,
                             userKey: SymmetricKeyPair, refreshToken: String?) async throws {
        UserDefaults.standard.set(serverKind.rawValue, forKey: "serverKind")
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
        UserDefaults.standard.set(email, forKey: "email")
        let custom: CustomURLs? = if case .custom(let urls) = environment { urls } else { nil }
        let id = SavedAccount.makeID(serverKind: serverKind.rawValue, serverURL: serverURL, email: email, customURLs: custom)
        let account = SavedAccount(id: id, email: email, serverKind: serverKind.rawValue, serverURL: serverURL,
                                   kdf: kdf, protectedUserKey: protectedUserKey, customURLs: custom)
        AccountStore.save(account)
        AccountStore.setRefreshToken(refreshToken, id)
        let session = open(account, key: userKey, client: client)
        self.client = nil
        try await session.refresh()
        addingAccount = false
        phase = .vault
    }

    // MARK: Single sign-on

    /// SSO handshake waiting for the master password.
    @ObservationIgnored private var pendingSSO: (client: VaultClient, session: VaultClient.SSOSession, environment: ServerEnvironment)?
    /// Shows the identity provider and returns the `bitwarden://sso-callback…` URL. Swapped in the self-test.
    @ObservationIgnored var ssoAuthenticator: @MainActor (URL) async throws -> URL = WebAuthentication.run

    func loginWithSSO(identifier: String) async {
        guard let environment = environment() else {
            errorMessage = serverURLProblem ?? String(localized: "Enter a valid server URL.")
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let client = makeClient(environment)
        do {
            let start = try await client.beginSSO(identifier: identifier)
            let callback = try await ssoAuthenticator(start.authorizeURL)
            let session = try await client.finishSSO(callback: callback, start: start)
            UserDefaults.standard.set(identifier, forKey: "ssoIdentifier")
            email = session.email
            pendingSSO = (client, session, environment)
            phase = .ssoPassword
        } catch WebAuthentication.Cancelled.byUser {
            // Closed the sign-in window: stay on the login form.
        } catch {
            handle(error)
        }
    }

    func completeSSO(password: String) async {
        guard let pending = pendingSSO else { phase = .login; return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let key = try await Task.detached { try pending.client.unlockSSO(pending.session, password: password) }.value
            try await finishLogin(environment: pending.environment, client: pending.client, kdf: pending.session.kdf,
                                  protectedUserKey: pending.session.protectedUserKey, userKey: key,
                                  refreshToken: pending.session.refreshToken)
            pendingSSO = nil
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
    /// - Parameter context: pass the context shown by an embedded Touch ID view to prompt inline.
    func unlockWithTouchID(context: LAContext = LAContext()) async {
        errorMessage = nil
        let locked = accounts.map(\.id).filter { !isUnlocked($0) }
        let keys = await AccountStore.unlockAllWithTouchID(locked, reason: String(localized: "unlock your vault"), context: context)
        if !keys.isEmpty { finishUnlock(keys) }
    }

    private func finishUnlock(_ keys: [String: SymmetricKeyPair]) {
        for (id, key) in keys {
            guard let account = accounts.first(where: { $0.id == id }) else { continue }
            let session = open(account, key: key)
            Task { await session.resume() }
        }
        noteActivity()
        // From the lock screen: the lock opens first, then the vault comes in. Instant for tooling and Reduce Motion.
        let tooling = CommandLine.arguments.contains { $0.hasPrefix("--selftest") || $0 == "--snapshot" }
        guard phase.id == Phase.locked.id, !tooling, Self.doorAnimates else {
            phase = .vault
            return
        }
        withAnimation(.spring(duration: 0.45, bounce: 0.35)) { unlockOpening = true }
        Task {
            // The door takes itself apart (~0.8 s, VaultDoorStage); then the lock layer dissolves over the vault.
            try? await Task.sleep(for: .milliseconds(780))
            phase = .vault
            try? await Task.sleep(for: .milliseconds(400))
            unlockOpening = false
        }
    }

    /// True for the moment between a successful unlock and the vault appearing (the lock-opening animation).
    var unlockOpening = false

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

    enum NewItemKind {
        case login, secureNote, card, identity, sshKey
        var itemKind: VaultItem.Kind {
            switch self { case .login: .login; case .secureNote: .note; case .card: .card; case .identity: .identity; case .sshKey: .sshKey }
        }
        var editorKind: CipherEditor.Kind {
            switch self { case .login: .login; case .secureNote: .secureNote; case .card: .card; case .identity: .identity; case .sshKey: .sshKey }
        }
    }

    /// Where new items go: the filtered account, else the first unlocked one.
    var defaultAccountId: String? { accountFilter ?? sessions.first?.id }

    @discardableResult
    func createItem(_ kind: NewItemKind, edit: CipherEdit, accountId: String? = nil) async -> Bool {
        guard let session = (accountId ?? defaultAccountId).flatMap(session(for:)) else { return offline() }
        do {
            let id = try await session.create(kind.editorKind, edit: edit)
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

    /// Creates a folder ("Parent/Child" nests) in the filtered or first account.
    @discardableResult
    func createFolder(name: String, accountId: String? = nil) async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let session = (accountId ?? defaultAccountId).flatMap(session(for:)) else { return nil }
        do {
            let id = try await session.createFolder(name: trimmed)
            flash(String(localized: "Folder created"))
            return id
        } catch { _ = failed(error); return nil }
    }

    func deleteFolder(_ id: String) async {
        guard let session = sessions.first(where: { $0.folders.contains { $0.id == id } }) else { return }
        do { try await session.deleteFolder(id) } catch { _ = failed(error) }
    }

    /// Moves items into a folder. A folder belongs to one account, so only that account's items move.
    func move(itemIDs: [String], toFolderIn folderIds: [String]) async {
        var moved = 0
        for id in itemIDs {
            guard let item = items.first(where: { $0.id == id }), let session = session(for: item),
                  let folderId = folderIds.first(where: { fid in session.folders.contains { $0.id == fid } }),
                  item.folderId != folderId else { continue }
            do { try await session.update(id, edit: CipherEdit(folderId: .some(folderId))); moved += 1 } catch { _ = failed(error); return }
        }
        if moved > 0 { flash(String(localized: "Moved \(moved) item(s)")) }
    }

    // MARK: Send

    func sendLink(_ send: SendItem) -> URL? {
        session(for: send.accountId)?.environment?.sendLink(accessId: send.accessId, keyMaterial: send.keyMaterial)
    }

    /// Creates a Send, copies its link and selects it.
    @discardableResult
    func createSend(_ draft: SendDraft, accountId: String?) async -> Bool {
        guard let session = accountId.flatMap({ session(for: $0) }) ?? sessions.first else { return offline() }
        do {
            let link = try await session.createSend(draft)
            if let link { copyPlain(link.absoluteString) }
            selectedSendID = sends.first { $0.name == draft.name && link?.absoluteString.contains($0.accessId) == true }?.id
            flash(String(localized: "Send created — link copied"))
            return true
        } catch { return failed(error) }
    }

    func deleteSend(_ send: SendItem) async {
        guard let session = session(for: send.accountId) else { _ = offline(); return }
        do {
            try await session.deleteSend(send.id)
            flash(String(localized: "Deleted “\(send.name)”"))
        } catch { _ = failed(error) }
    }

    // MARK: Attachments

    /// Decrypted copy being previewed with Quick Look; deleted when the preview closes or on lock.
    var previewURL: URL?
    var attachmentBusy: Set<String> = []
    /// Bitwarden's per-file limit; also keeps the whole file comfortably in memory.
    static let attachmentLimit = 500 * 1_024 * 1_024

    func previewAttachment(_ attachment: VaultItem.Attachment, of item: VaultItem) async {
        guard let data = await attachmentContents(attachment, of: item) else { return }
        do { previewURL = try AttachmentFiles.write(data, named: attachment.fileName) } catch { _ = failed(error) }
    }

    func saveAttachment(_ attachment: VaultItem.Attachment, of item: VaultItem) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.fileName
        guard panel.runModal() == .OK, let url = panel.url,
              let data = await attachmentContents(attachment, of: item) else { return }
        do {
            try data.write(to: url, options: .atomic)
            flash(String(localized: "Saved “\(attachment.fileName)”"))
        } catch { _ = failed(error) }
    }

    private func attachmentContents(_ attachment: VaultItem.Attachment, of item: VaultItem) async -> Data? {
        guard let session = session(for: item) else { _ = offline(); return nil }
        attachmentBusy.insert(attachment.id)
        defer { attachmentBusy.remove(attachment.id) }
        noteActivity()
        do { return try await session.attachmentContents(item.id, attachment) } catch { _ = failed(error); return nil }
    }

    @discardableResult
    func addAttachments(_ urls: [URL], to item: VaultItem) async -> Bool {
        guard let session = session(for: item) else { return offline() }
        attachmentBusy.insert(item.id)
        defer { attachmentBusy.remove(item.id) }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= Self.attachmentLimit else {
                    flash(String(localized: "“\(url.lastPathComponent)” is larger than 500 MB."))
                    continue
                }
                try await session.addAttachment(item.id, name: url.lastPathComponent, contents: Data(contentsOf: url))
                flash(String(localized: "Attached “\(url.lastPathComponent)”"))
            } catch { return failed(error) }
        }
        return true
    }

    func deleteAttachment(_ attachment: VaultItem.Attachment, of item: VaultItem) async {
        guard let session = session(for: item) else { _ = offline(); return }
        do {
            try await session.deleteAttachment(item.id, attachment.id)
            flash(String(localized: "Deleted “\(attachment.fileName)”"))
        } catch { _ = failed(error) }
    }

    func toggleFavorite(_ item: VaultItem) async {
        // `--demo` / previews have no server: apply it here so the UI (and its tests) still work.
        if sessions.isEmpty, previewUnlocked, let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i].favorite.toggle()
            return
        }
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

    /// Locks every account. `animated` (a lock the user asked for): the keys go at once, but the vault's contents stay
    /// on screen a moment longer, so the door can close over them before they're cleared.
    func lock(animated: Bool = false) {
        previewURL = nil
        generatorHistory = []
        AttachmentFiles.wipe()
        sshAgent?.reset()
        cli?.reset()
        breachCounts = nil
        breachesCheckedAt = nil
        sessions.forEach { $0.close() }
        sessions = []
        refreshAccounts()
        addingAccount = false
        let tooling = CommandLine.arguments.contains { $0.hasPrefix("--selftest") || $0 == "--snapshot" }
        let closing = animated && phase.id == Phase.vault.id && !accounts.isEmpty && !tooling && Self.doorAnimates
        phase = accounts.isEmpty ? .login : .locked
        guard closing else { clearVaultContents(); return }
        lockClosing = true
        Task {
            // The lock layer's closing sequence (VaultDoorStage) runs ~1 s; the vault is covered well before that.
            try? await Task.sleep(for: .milliseconds(650))
            lockClosing = false
            if sessions.isEmpty { clearVaultContents() } // unless Touch ID already opened it again
        }
    }

    /// The vault door's open/close sequences: off with Reduce Motion or Settings › Security › Animate the vault door.
    static var doorAnimates: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && UserDefaults.standard.bool(forKey: Pref.lockAnimations)
    }

    /// True while the lock layer closes over the vault (an animated lock).
    var lockClosing = false

    private func clearVaultContents() {
        selectedID = nil
        accountFilter = nil
        items = []
        sends = []
        selectedSendID = nil
        folders = []
        organizations = []
    }

    func cancelChallenge() {
        errorMessage = nil
        pendingSSO = nil
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
