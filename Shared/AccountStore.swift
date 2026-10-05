import ChiikawaCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import Security
import VaultwardenAPI

/// What we keep on disk to unlock without the network. Nothing here decrypts the vault on its own:
/// `protectedUserKey` needs the master password (or the Secure Enclave, for Touch ID).
struct SavedAccount: Codable, Equatable {
    var email: String
    var serverKind: String
    var serverURL: String
    var kdf: KDFConfig
    var protectedUserKey: String
}

enum AccountStore {
    /// Shared with the AutoFill extension (team-prefixed group: no provisioning needed on macOS).
    static let appGroup = "FX3VR69P5K.io.github.sinhong2011.chiikawarden"

    private static var dir: URL {
        let fm = FileManager.default
        let legacy = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Account", directoryHint: .isDirectory)
        guard let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return legacy }
        let d = group.appending(path: "Account", directoryHint: .isDirectory)
        // One-time move from the pre-AutoFill location.
        if !fm.fileExists(atPath: d.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: d)
        }
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Offline unlock: re-derive the master key; the MAC on the protected user key proves the password.
    static func unlock(password: String) -> SymmetricKeyPair? {
        guard let saved = load(),
              let mk = try? KDF.masterKey(password: password, email: saved.email, config: saved.kdf),
              let stretched = try? SymmetricKeyPair.stretched(masterKey: mk),
              let raw = try? EncString(saved.protectedUserKey).decrypt(with: stretched) else { return nil }
        return try? SymmetricKeyPair(combined: raw)
    }
    private static var accountURL: URL { dir.appending(path: "account.json") }
    private static var cacheURL: URL { dir.appending(path: "vault.json") }
    private static var biometricURL: URL { dir.appending(path: "biometric.json") }

    static func load() -> SavedAccount? {
        (try? Data(contentsOf: accountURL)).flatMap { try? JSONDecoder().decode(SavedAccount.self, from: $0) }
    }

    static func save(_ account: SavedAccount) {
        try? JSONEncoder().encode(account).write(to: accountURL, options: [.atomic, .completeFileProtection])
    }

    /// Encrypted sync payload, exactly as the server sent it.
    static func loadCache() -> Data? { try? Data(contentsOf: cacheURL) }
    static func saveCache(_ data: Data) { try? data.write(to: cacheURL, options: [.atomic, .completeFileProtection]) }

    static func erase() {
        try? FileManager.default.removeItem(at: dir)
        Keychain.delete(service: refreshService)
    }

    // MARK: Refresh token (Keychain)

    private static let refreshService = "io.github.sinhong2011.chiikawarden.refresh"
    static var refreshToken: String? {
        get { Keychain.read(service: refreshService).flatMap { String(data: $0, encoding: .utf8) } }
        set {
            if let newValue { Keychain.write(Data(newValue.utf8), service: refreshService) } else { Keychain.delete(service: refreshService) }
        }
    }

    // MARK: Touch ID (Secure Enclave)

    /// The user key, sealed with a key derived from a biometry-gated Secure Enclave key.
    private struct BiometricBlob: Codable {
        var enclaveKey: Data      // SecureEnclave key handle (useless off this Mac / without Touch ID)
        var ephemeralPublic: Data // peer for key agreement
        var sealed: Data          // AES-GCM(userKey)
    }

    static var isTouchIDEnabled: Bool { FileManager.default.fileExists(atPath: biometricURL.path) }

    static var isTouchIDAvailable: Bool {
        SecureEnclave.isAvailable && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func enableTouchID(userKey: SymmetricKeyPair) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           [.privateKeyUsage, .biometryCurrentSet], &error) else {
            throw error!.takeRetainedValue() as Error
        }
        let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        let ephemeral = P256.KeyAgreement.PrivateKey()
        // Wrapping only needs the enclave *public* key, so no prompt here.
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: enclave.publicKey)
        let wrapKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("chiikawarden-touchid".utf8),
                                                     sharedInfo: Data(), outputByteCount: 32)
        let sealed = try AES.GCM.seal(userKey.encryptionKey + userKey.macKey, using: wrapKey).combined!
        let blob = BiometricBlob(enclaveKey: enclave.dataRepresentation,
                                 ephemeralPublic: ephemeral.publicKey.rawRepresentation, sealed: sealed)
        try JSONEncoder().encode(blob).write(to: biometricURL, options: [.atomic, .completeFileProtection])
    }

    static func disableTouchID() { try? FileManager.default.removeItem(at: biometricURL) }

    /// Prompts for Touch ID (via the Secure Enclave) and returns the user key.
    static func unlockWithTouchID(reason: String) throws -> SymmetricKeyPair {
        let blob = try JSONDecoder().decode(BiometricBlob.self, from: Data(contentsOf: biometricURL))
        let context = LAContext()
        context.localizedReason = reason
        let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: blob.enclaveKey,
                                                                      authenticationContext: context)
        let peer = try P256.KeyAgreement.PublicKey(rawRepresentation: blob.ephemeralPublic)
        let shared = try enclave.sharedSecretFromKeyAgreement(with: peer)
        let wrapKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("chiikawarden-touchid".utf8),
                                                     sharedInfo: Data(), outputByteCount: 32)
        let raw = try AES.GCM.open(AES.GCM.SealedBox(combined: blob.sealed), using: wrapKey)
        return try SymmetricKeyPair(combined: raw)
    }
}

/// Minimal generic-password Keychain helper.
enum Keychain {
    static func read(service: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func write(_ data: Data, service: String) {
        delete(service: service)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecValueData as String: data,
                                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(service: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}
