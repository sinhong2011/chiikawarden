import CommonCrypto
import CryptoKit
import Foundation

/// A Bitwarden encrypted string: `<type>.<b64 iv>|<b64 ciphertext>|<b64 mac>`.
///
/// Only type 2 (AES-256-CBC + HMAC-SHA256) is supported for symmetric data; the legacy
/// MAC-less types are rejected on purpose.
public struct EncString: Sendable, Equatable, CustomStringConvertible {
    public static let aesCbc256HmacSha256 = 2

    public let type: Int
    public let iv: Data
    public let ciphertext: Data
    public let mac: Data

    public init(_ string: String) throws(CryptoError) {
        guard let dot = string.firstIndex(of: "."), let type = Int(string[..<dot]) else {
            throw .malformedEncString
        }
        guard type == Self.aesCbc256HmacSha256 else { throw .unsupportedEncType(type) }
        let parts = string[string.index(after: dot)...].split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let iv = Data(base64Encoded: String(parts[0])),
              let ct = Data(base64Encoded: String(parts[1])),
              let mac = Data(base64Encoded: String(parts[2])),
              iv.count == 16, mac.count == 32
        else { throw .malformedEncString }
        self.type = type
        self.iv = iv
        self.ciphertext = ct
        self.mac = mac
    }

    init(iv: Data, ciphertext: Data, mac: Data) {
        self.type = Self.aesCbc256HmacSha256
        self.iv = iv
        self.ciphertext = ciphertext
        self.mac = mac
    }

    public var description: String {
        "\(type).\(iv.base64EncodedString())|\(ciphertext.base64EncodedString())|\(mac.base64EncodedString())"
    }

    public func decrypt(with key: SymmetricKeyPair) throws(CryptoError) -> Data {
        let expected = Self.hmac(key: key.macKey, iv: iv, ciphertext: ciphertext)
        // Constant-time comparison before touching the ciphertext.
        guard Self.constantTimeEqual(expected, mac) else { throw .macMismatch }
        return try Self.aesCBC(CCOperation(kCCDecrypt), key: key.encryptionKey, iv: iv, input: ciphertext)
    }

    public func decryptString(with key: SymmetricKeyPair) throws(CryptoError) -> String {
        guard let s = String(data: try decrypt(with: key), encoding: .utf8) else { throw .malformedEncString }
        return s
    }

    public static func encrypt(_ plaintext: Data, with key: SymmetricKeyPair) throws(CryptoError) -> EncString {
        var iv = Data(count: 16)
        let rc = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard rc == errSecSuccess else { throw .commonCrypto(rc) }
        let ct = try aesCBC(CCOperation(kCCEncrypt), key: key.encryptionKey, iv: iv, input: plaintext)
        return EncString(iv: iv, ciphertext: ct, mac: hmac(key: key.macKey, iv: iv, ciphertext: ct))
    }

    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }

    static func hmac(key: Data, iv: Data, ciphertext: Data) -> Data {
        var h = HMAC<SHA256>(key: SymmetricKey(data: key))
        h.update(data: iv)
        h.update(data: ciphertext)
        return Data(h.finalize())
    }

    static func aesCBC(_ op: CCOperation, key: Data, iv: Data, input: Data) throws(CryptoError) -> Data {
        var out = Data(count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let outCapacity = out.count
        let status = out.withUnsafeMutableBytes { o in
            input.withUnsafeBytes { i in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { v in
                        CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress, key.count, v.baseAddress,
                                i.baseAddress, input.count, o.baseAddress, outCapacity, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw .commonCrypto(status) }
        return out.prefix(moved)
    }
}

/// Binary form of a type-2 EncString used for attachment and Send file contents:
/// `[type: 1 byte][iv: 16][mac: 32][ciphertext]`.
public enum EncArrayBuffer {
    public static func encrypt(_ plaintext: Data, with key: SymmetricKeyPair) throws(CryptoError) -> Data {
        let e = try EncString.encrypt(plaintext, with: key)
        return Data([UInt8(EncString.aesCbc256HmacSha256)]) + e.iv + e.mac + e.ciphertext
    }

    public static func decrypt(_ buffer: Data, with key: SymmetricKeyPair) throws(CryptoError) -> Data {
        let b = Data(buffer) // rebase indices to 0
        guard b.count > 49, Int(b[0]) == EncString.aesCbc256HmacSha256 else { throw .malformedEncString }
        let iv = b[1..<17], mac = b[17..<49], ct = b[49...]
        let expected = EncString.hmac(key: key.macKey, iv: Data(iv), ciphertext: Data(ct))
        guard EncString.constantTimeEqual(expected, Data(mac)) else { throw .macMismatch }
        return try EncString.aesCBC(CCOperation(kCCDecrypt), key: key.encryptionKey, iv: Data(iv), input: Data(ct))
    }
}
