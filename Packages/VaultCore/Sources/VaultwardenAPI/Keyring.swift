import TriCrypto
import Foundation

/// Resolves the key for each cipher: user key, org key, or a per-item key wrapped by either.
public struct Keyring: Sendable {
    public let userKey: SymmetricKeyPair
    public private(set) var orgKeys: [String: SymmetricKeyPair] = [:]
    /// Orgs whose key couldn't be unwrapped (shown as hidden items, never crash).
    public private(set) var failedOrgs: Set<String> = []

    public init(userKey: SymmetricKeyPair, profile: SyncResponse.Profile) {
        self.userKey = userKey
        guard let encPrivate = profile.privateKey,
              let der = try? EncString(encPrivate).decrypt(with: userKey),
              let rsa = try? RSAPrivateKey(pkcs8: der) else {
            failedOrgs = Set(profile.organizations?.map(\.id) ?? [])
            return
        }
        for org in profile.organizations ?? [] {
            if let wrapped = org.key, let raw = try? rsa.decrypt(wrapped), let key = try? SymmetricKeyPair(combined: raw) {
                orgKeys[org.id] = key
            } else {
                failedOrgs.insert(org.id)
            }
        }
    }

    /// The key that decrypts this cipher's fields, or nil if unavailable.
    public func key(for cipher: SyncResponse.Cipher) -> SymmetricKeyPair? {
        let owner: SymmetricKeyPair? = cipher.organizationId.map { orgKeys[$0] } ?? userKey
        guard let owner else { return nil }
        guard let itemKey = cipher.key else { return owner }
        return (try? EncString(itemKey).decrypt(with: owner)).flatMap { try? SymmetricKeyPair(combined: $0) }
    }
}
