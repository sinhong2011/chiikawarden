import ChiikawaCrypto
import Foundation
import Observation
import VaultwardenAPI

struct VaultItem: Identifiable, Hashable {
    let id: String
    let name: String
    let username: String?
    let host: String?
    let hasTOTP: Bool
    let favorite: Bool
}

@MainActor @Observable
final class AppModel {
    enum Phase {
        case login
        case twoFactor(providers: [String])
        case vault
        var id: Int {
            switch self { case .login: 0; case .twoFactor: 1; case .vault: 2 }
        }
    }

    var phase: Phase = .login
    var items: [VaultItem] = []
    var skippedOrgItems = 0
    var isBusy = false
    var errorMessage: String?

    var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "https://"
    var email = UserDefaults.standard.string(forKey: "email") ?? ""

    var isUnlocked: Bool { phase.id == Phase.vault.id }

    private var client: VaultwardenClient?
    private var userKey: SymmetricKeyPair?

    private var deviceIdentifier: String {
        if let id = UserDefaults.standard.string(forKey: "deviceIdentifier") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "deviceIdentifier")
        return id
    }

    func login(password: String, twoFactorCode: String? = nil) async {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)), url.host() != nil else {
            errorMessage = String(localized: "Enter a valid server URL.")
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let client = self.client?.baseURL == url ? self.client! : VaultwardenClient(baseURL: url, deviceIdentifier: deviceIdentifier)
        self.client = client
        do {
            // Provider "0" is the authenticator app (TOTP).
            let key = try await client.login(email: email, password: password,
                                             twoFactor: twoFactorCode.map { ("0", $0) })
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
        var skipped = 0
        items = sync.ciphers.compactMap { cipher in
            guard cipher.deletedDate == nil else { return nil }
            // Org ciphers need the RSA-wrapped org keys; that lands after M0.
            guard cipher.organizationId == nil else { skipped += 1; return nil }
            func dec(_ s: String?) -> String? { s.flatMap { try? EncString($0).decryptString(with: userKey) } }
            return VaultItem(
                id: cipher.id,
                name: dec(cipher.name) ?? "—",
                username: dec(cipher.login?.username),
                host: dec(cipher.login?.uris?.first?.uri).flatMap { URL(string: $0)?.host() },
                hasTOTP: cipher.login?.totp != nil,
                favorite: cipher.favorite ?? false
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        skippedOrgItems = skipped
    }

    func lock() {
        userKey = nil
        items = []
        phase = .login
    }

    private func handle(_ error: Error) {
        switch error as? APIError {
        case .twoFactorRequired(let providers)?:
            phase = .twoFactor(providers: providers)
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
