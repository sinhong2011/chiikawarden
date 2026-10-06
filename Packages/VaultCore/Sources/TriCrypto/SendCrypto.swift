import CryptoKit
import Foundation
import Security

/// Bitwarden Send keys. Each Send has 16 random bytes of key material: it is stored encrypted with the
/// user key, travels in the share link's fragment (never to the server), and derives the key that
/// encrypts the Send's name, text and file.
public enum SendCrypto {
    public static func newKeyMaterial() throws(CryptoError) -> Data {
        var bytes = Data(count: 16)
        let rc = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard rc == errSecSuccess else { throw .commonCrypto(rc) }
        return bytes
    }

    /// HKDF-SHA256(ikm: key material, salt: "bitwarden-send", info: "send") → 64-byte enc+mac key.
    public static func key(from keyMaterial: Data) throws(CryptoError) -> SymmetricKeyPair {
        let derived = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: keyMaterial),
                                             salt: Data("bitwarden-send".utf8), info: Data("send".utf8), outputByteCount: 64)
        return try SymmetricKeyPair(combined: derived.withUnsafeBytes { Data($0) })
    }

    /// What the server stores and checks for a password-protected Send:
    /// base64(PBKDF2-SHA256(password, salt: key material, 100 000 rounds, 32 bytes)).
    public static func passwordHash(_ password: String, keyMaterial: Data) throws(CryptoError) -> String {
        try KDF.pbkdf2SHA256(password: Data(password.utf8), salt: keyMaterial, iterations: 100_000, length: 32).base64EncodedString()
    }
}
