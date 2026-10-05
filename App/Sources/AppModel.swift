import AppKit
import ChiikawaCrypto
import Foundation
import Observation
import VaultwardenAPI

struct VaultItem: Identifiable, Hashable {
    enum Kind: Int { case login = 1, note = 2, card = 3, identity = 4, sshKey = 5 }

    let id: String
    var kind: Kind = .login
    let name: String
    var username: String?
    let host: String?
    let password: String?
    let totp: TOTP?
    let notes: String?
    let favorite: Bool
    var hasPasskey = false
    /// Filled in after sync: how many other items share this password.
    var reuseCount = 0

    var hasTOTP: Bool { totp != nil }

    /// Extra fields for non-login kinds (card, identity, SSH key), in display order.
    var fields: [ItemField] = []

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct ItemField: Hashable, Identifiable {
    var id: String { label }
    let label: String
    let value: String
    var secret = false
    var monospaced = false
}

extension TOTP: @retroactive Hashable {
    public func hash(into h: inout Hasher) { h.combine(secret) }
}

@MainActor @Observable
final class AppModel {
    enum Phase {
        case login
        case twoFactor(providers: [String])
        /// Official cloud emailed a one-time code for this new device.
        case deviceVerification
        case vault
        var id: Int {
            switch self { case .login: 0; case .twoFactor: 1; case .deviceVerification: 3; case .vault: 2 }
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
    var skippedOrgItems = 0
    var isBusy = false
    var errorMessage: String?

    var serverKind = ServerKind(rawValue: UserDefaults.standard.string(forKey: "serverKind") ?? "") ?? .selfHosted
    var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "https://"
    var email = UserDefaults.standard.string(forKey: "email") ?? ""

    var isUnlocked: Bool { phase.id == Phase.vault.id }

    enum ServerStatus: Equatable {
        case unknown, checking
        case reachable(product: String, version: String?)
        case unreachable(String)
    }
    var serverStatus: ServerStatus = .unknown
    private var statusTask: Task<Void, Never>?

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
        let cas = UserDefaults.standard.array(forKey: Pref.trustedCAs) as? [Data] ?? []
        let session = cas.isEmpty ? URLSession.shared : ServerTrust(certificates: cas).makeSession()
        return VaultClient(environment: environment, deviceIdentifier: deviceIdentifier,
                           extraHeaders: HeaderStore.dictionary, session: session)
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

    /// Lock and forget the remembered account on this Mac.
    func logOut() {
        lock()
        client = nil
        email = ""
        UserDefaults.standard.removeObject(forKey: "email")
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
            let key = try await client.login(email: email, password: password,
                                             twoFactor: isDeviceCode ? nil : code.map { ("0", $0) },
                                             newDeviceOTP: isDeviceCode ? code : nil)
            UserDefaults.standard.set(serverKind.rawValue, forKey: "serverKind")
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            UserDefaults.standard.set(email, forKey: "email")
            userKey = key
            try await refresh()
            phase = .vault
        } catch {
            handle(error)
        }
    }

    func refresh() async throws {
        guard let client, let userKey else { return }
        let sync = try await client.sync()
        let keyring = Keyring(userKey: userKey, profile: sync.profile)
        var hidden = 0
        items = sync.ciphers.compactMap { cipher in
            guard cipher.deletedDate == nil else { return nil }
            guard let key = keyring.key(for: cipher) else { hidden += 1; return nil }
            func dec(_ s: String?) -> String? {
                s.flatMap { try? EncString($0).decryptString(with: key) }.flatMap { $0.isEmpty ? nil : $0 }
            }
            let kind = VaultItem.Kind(rawValue: cipher.type) ?? .login
            var item = VaultItem(
                id: cipher.id,
                kind: kind,
                name: dec(cipher.name) ?? "—",
                username: dec(cipher.login?.username),
                host: dec(cipher.login?.uris?.first?.uri).flatMap { URL(string: $0)?.host() },
                password: dec(cipher.login?.password),
                totp: dec(cipher.login?.totp).flatMap(TOTP.init),
                notes: dec(cipher.notes),
                favorite: cipher.favorite ?? false,
                hasPasskey: !(cipher.login?.fido2Credentials ?? []).isEmpty
            )
            switch kind {
            case .card:
                let c = cipher.card
                let number = dec(c?.number)
                let month = dec(c?.expMonth), year = dec(c?.expYear)
                item.username = number.map { "•••• " + $0.suffix(4) } ?? dec(c?.brand)
                item.fields = [
                    number.map { ItemField(label: String(localized: "Card number"), value: $0, secret: true, monospaced: true) },
                    dec(c?.cardholderName).map { ItemField(label: String(localized: "Cardholder"), value: $0) },
                    (month != nil || year != nil) ? ItemField(label: String(localized: "Expires"), value: "\(month ?? "--")/\(year ?? "----")") : nil,
                    dec(c?.code).map { ItemField(label: String(localized: "Security code"), value: $0, secret: true, monospaced: true) },
                ].compactMap { $0 }
            case .identity:
                let i = cipher.identity
                let name = [dec(i?.title), dec(i?.firstName), dec(i?.middleName), dec(i?.lastName)].compactMap { $0 }.joined(separator: " ")
                item.username = name.isEmpty ? dec(i?.email) : name
                item.fields = [
                    name.isEmpty ? nil : ItemField(label: String(localized: "Name"), value: name),
                    dec(i?.email).map { ItemField(label: String(localized: "Email"), value: $0) },
                    dec(i?.phone).map { ItemField(label: String(localized: "Phone"), value: $0) },
                    dec(i?.company).map { ItemField(label: String(localized: "Company"), value: $0) },
                    dec(i?.username).map { ItemField(label: String(localized: "Username"), value: $0) },
                    [dec(i?.address1), dec(i?.city), dec(i?.country)].compactMap { $0 }.joined(separator: ", ")
                        .nilIfEmpty.map { ItemField(label: String(localized: "Address"), value: $0) },
                ].compactMap { $0 }
            case .sshKey:
                let k = cipher.sshKey
                item.username = dec(k?.keyFingerprint)
                item.fields = [
                    dec(k?.publicKey).map { ItemField(label: String(localized: "Public key"), value: $0, monospaced: true) },
                    dec(k?.keyFingerprint).map { ItemField(label: String(localized: "Fingerprint"), value: $0, monospaced: true) },
                    dec(k?.privateKey).map { ItemField(label: String(localized: "Private key"), value: $0, secret: true, monospaced: true) },
                ].compactMap { $0 }
            case .note:
                item.username = item.notes.map { String($0.prefix(60)) }
            case .login:
                break
            }
            return item
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let counts = Dictionary(items.compactMap(\.password).map { ($0, 1) }, uniquingKeysWith: +)
        for i in items.indices {
            if let pw = items[i].password { items[i].reuseCount = (counts[pw] ?? 1) - 1 }
        }
        skippedOrgItems = hidden
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
        userKey = nil
        items = []
        phase = .login
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

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
