import ChiikawaCrypto
import Foundation

// Endpoints beyond the vault basics: organizations, bulk edits, account security, devices, two-step login,
// sign-in requests, emergency access, equivalent domains and event logs. Bodies and answers are plain JSON
// (already encrypted where they hold secrets); callers decode what they need.

extension VaultClient {
    /// An authorized call to the API with an optional JSON body; returns the answer's bytes.
    @discardableResult
    public func call(_ method: String, _ path: String, json body: Any? = nil) async throws(APIError) -> Data {
        var r = try request(environment.apiURL, path)
        r.httpMethod = method
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do { r.httpBody = try JSONSerialization.data(withJSONObject: body) } catch { throw .http(status: -1, message: "encode") }
        }
        return try await sendRaw(authorized(r))
    }

    /// The same, decoded as a JSON object (camelCase keys, whatever case the server used).
    public func callJSON(_ method: String, _ path: String, json body: Any? = nil) async throws(APIError) -> [String: Any] {
        let data = try await call(method, path, json: body)
        guard !data.isEmpty else { return [:] }
        return (CipherEditor.normalize(try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }

    // MARK: Organizations and bulk edits

    /// Moves a personal item into an organization (`cipher` re-encrypted with the organization key, see
    /// `CipherEditor.sharedCipher`), into the given collections.
    public func shareCipher(id: String, cipher: [String: Any], collectionIds: [String]) async throws(APIError) {
        try await call("PUT", "ciphers/\(id)/share", json: ["cipher": cipher, "collectionIds": collectionIds])
    }

    /// Sets which collections an organization item is in.
    public func setCollections(cipherId: String, collectionIds: [String]) async throws(APIError) {
        try await call("PUT", "ciphers/\(cipherId)/collections_v2", json: ["collectionIds": collectionIds])
    }

    /// Moves personal items into a folder (nil: out of any folder).
    public func moveCiphers(ids: [String], folderId: String?) async throws(APIError) {
        try await call("PUT", "ciphers/move", json: ["ids": ids, "folderId": folderId ?? NSNull()] as [String: Any])
    }

    public func trashCiphers(ids: [String]) async throws(APIError) { try await call("PUT", "ciphers/delete", json: ["ids": ids]) }
    public func restoreCiphers(ids: [String]) async throws(APIError) { try await call("PUT", "ciphers/restore", json: ["ids": ids]) }
    public func deleteCiphers(ids: [String]) async throws(APIError) { try await call("DELETE", "ciphers", json: ["ids": ids]) }
    public func archiveCiphers(ids: [String]) async throws(APIError) { try await call("PUT", "ciphers/archive", json: ["ids": ids]) }

    public func leaveOrganization(id: String) async throws(APIError) { try await call("POST", "organizations/\(id)/leave") }

    // MARK: Sends

    /// Changes a Send (body from `SendDraft.seal(userKey:keyMaterial:)` with its own key material; a file Send's file
    /// stays as it is). A nil password keeps the current one.
    public func updateSend(id: String, body: Data) async throws(APIError) {
        guard let object = try? JSONSerialization.jsonObject(with: body) else { throw .http(status: -1, message: "encode") }
        try await call("PUT", "sends/\(id)", json: object)
    }

    public func removeSendPassword(id: String) async throws(APIError) { try await call("PUT", "sends/\(id)/remove-password") }

    // MARK: Account security

    /// The account's public key (base64 SubjectPublicKeyInfo), as the server holds it.
    public func publicKey(userId: String) async throws(APIError) -> String? {
        try await callJSON("GET", "users/\(userId)/public-key")["publicKey"] as? String
    }

    /// Devices signed in to the account.
    public func devices() async throws(APIError) -> [DeviceInfo] {
        (try await callJSON("GET", "devices")["data"] as? [[String: Any]] ?? []).compactMap(DeviceInfo.init)
    }

    /// Signs out every session (this one too).
    public func deauthorizeSessions(masterPasswordHash: String) async throws(APIError) {
        try await call("POST", "accounts/security-stamp", json: ["masterPasswordHash": masterPasswordHash])
    }

    /// Changes the master password, or the KDF (`changeKDF`): the new login hash and the user key wrapped with the new
    /// master key. Sends both the current shape and the older one (`newMasterPasswordHash`, `key`).
    public func changeMasterPassword(currentHash: String, change: MasterPasswordChange, hint: String?) async throws(APIError) {
        var body = change.body(currentHash: currentHash)
        body["masterPasswordHint"] = hint ?? NSNull()
        try await call("POST", "accounts/password", json: body)
    }

    public func changeKDF(currentHash: String, change: MasterPasswordChange) async throws(APIError) {
        try await call("POST", "accounts/kdf", json: change.body(currentHash: currentHash))
    }

    // MARK: Two-step login

    /// Each provider's type and whether it's on (0 authenticator, 1 email, 7 WebAuthn, 3 YubiKey, 2 Duo…).
    public func twoFactorProviders() async throws(APIError) -> [Int: Bool] {
        let list = try await callJSON("GET", "two-factor")["data"] as? [[String: Any]] ?? []
        return Dictionary(list.compactMap { p in (p["type"] as? Int).map { ($0, p["enabled"] as? Bool ?? false) } }, uniquingKeysWith: { a, _ in a })
    }

    /// A new authenticator secret to scan (or the current one), and whether it's on.
    public func authenticatorSecret(masterPasswordHash: String) async throws(APIError) -> (key: String, enabled: Bool) {
        let answer = try await callJSON("POST", "two-factor/get-authenticator", json: ["masterPasswordHash": masterPasswordHash])
        return (answer["key"] as? String ?? "", answer["enabled"] as? Bool ?? false)
    }

    public func enableAuthenticator(key: String, code: String, masterPasswordHash: String) async throws(APIError) {
        try await call("PUT", "two-factor/authenticator", json: ["key": key, "token": code, "masterPasswordHash": masterPasswordHash])
    }

    public func disableTwoFactor(type: Int, masterPasswordHash: String) async throws(APIError) {
        try await call("PUT", "two-factor/disable", json: ["type": type, "masterPasswordHash": masterPasswordHash] as [String: Any])
    }

    /// The one-time recovery code that turns two-step login off if every method is lost.
    public func twoFactorRecoveryCode(masterPasswordHash: String) async throws(APIError) -> String? {
        try await callJSON("POST", "two-factor/get-recover", json: ["masterPasswordHash": masterPasswordHash])["code"] as? String
    }

    public func emailTwoFactor(masterPasswordHash: String) async throws(APIError) -> (email: String?, enabled: Bool) {
        let answer = try await callJSON("POST", "two-factor/get-email", json: ["masterPasswordHash": masterPasswordHash])
        return (answer["email"] as? String, answer["enabled"] as? Bool ?? false)
    }

    public func sendTwoFactorEmail(to email: String, masterPasswordHash: String) async throws(APIError) {
        try await call("POST", "two-factor/send-email", json: ["email": email, "masterPasswordHash": masterPasswordHash])
    }

    public func enableEmailTwoFactor(email: String, code: String, masterPasswordHash: String) async throws(APIError) {
        try await call("PUT", "two-factor/email", json: ["email": email, "token": code, "masterPasswordHash": masterPasswordHash])
    }
}

/// A new master password or KDF: what the server stores (login hash, user key wrapped with the new master key).
public struct MasterPasswordChange: Sendable {
    public let email: String
    public let kdf: KDFConfig
    public let newHash: String
    public let protectedUserKey: String

    public init(email: String, newPassword: String, kdf: KDFConfig, userKey: SymmetricKeyPair) throws {
        let salt = KDF.normalizedEmail(email)
        let master = try KDF.masterKey(password: newPassword, email: salt, config: kdf)
        self.email = salt
        self.kdf = kdf
        newHash = try KDF.masterPasswordHash(masterKey: master, password: newPassword)
        protectedUserKey = try EncString.encrypt(userKey.encryptionKey + userKey.macKey,
                                                 with: SymmetricKeyPair.stretched(masterKey: master)).description
    }

    var kdfJSON: [String: Any] {
        switch kdf {
        case .pbkdf2(let iterations): ["kdf": 0, "kdfIterations": iterations, "kdfMemory": NSNull(), "kdfParallelism": NSNull()]
        case .argon2id(let iterations, let memory, let parallelism):
            ["kdf": 1, "kdfIterations": iterations, "kdfMemory": memory, "kdfParallelism": parallelism]
        }
    }

    func body(currentHash: String) -> [String: Any] {
        [
            "masterPasswordHash": currentHash,
            "authenticationData": ["salt": email, "kdf": kdfJSON, "masterPasswordAuthenticationHash": newHash] as [String: Any],
            "unlockData": ["salt": email, "kdf": kdfJSON, "masterKeyWrappedUserKey": protectedUserKey] as [String: Any],
            "newMasterPasswordHash": newHash,
            "key": protectedUserKey,
        ]
    }
}

/// A device signed in to the account.
public struct DeviceInfo: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    /// Bitwarden's device type: 7 macOS desktop, 9 Chrome, 14 web vault, 0 Android, 1 iOS…
    public let type: Int
    public let identifier: String
    public let created: String?
    public let lastActive: String?

    init?(_ d: [String: Any]) {
        guard let id = d["id"] as? String else { return nil }
        self.id = id
        name = d["name"] as? String ?? ""
        type = d["type"] as? Int ?? -1
        identifier = d["identifier"] as? String ?? ""
        created = d["creationDate"] as? String
        lastActive = (d["lastActivityDate"] ?? d["revisionDate"]) as? String
    }

    /// A short kind, for an icon and a label.
    public var kind: String {
        switch type {
        case 0, 15: "android"
        case 1: "ios"
        case 5, 6, 7, 16: "desktop"
        case 2, 3, 4, 19, 20: "extension"
        case 8, 9, 10, 11, 12, 13, 14, 17, 18: "browser"
        case 21...25: "cli"
        default: "other"
        }
    }
}
