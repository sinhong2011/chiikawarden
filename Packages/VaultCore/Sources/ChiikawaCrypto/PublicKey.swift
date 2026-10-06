import CryptoKit
import Foundation
import Security

extension RSAPrivateKey {
    /// A new 2048-bit key (a device asking to sign in keeps it until the answer arrives).
    public static func generate() throws(CryptoError) -> RSAPrivateKey {
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, nil),
              let pkcs1 = SecKeyCopyExternalRepresentation(key, nil) as Data? else { throw .malformedEncString }
        let algorithm: [UInt8] = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
        let pkcs8 = RSAPublicKey.der(tag: 0x30, [0x02, 0x01, 0x00] + algorithm + RSAPublicKey.der(tag: 0x04, Array(pkcs1)))
        return try RSAPrivateKey(pkcs8: Data(pkcs8))
    }

    /// The matching public key as SubjectPublicKeyInfo DER — the form Bitwarden stores and hashes.
    public func publicKeySPKI() throws(CryptoError) -> Data {
        guard let pub = SecKeyCopyPublicKey(key), let pkcs1 = SecKeyCopyExternalRepresentation(pub, nil) as Data? else {
            throw .malformedEncString
        }
        return RSAPublicKey.spki(fromPKCS1: pkcs1)
    }
}

/// Someone else's RSA public key (a device asking to sign in, an emergency contact): wraps a key for them.
public struct RSAPublicKey: @unchecked Sendable {
    let key: SecKey
    public let spki: Data

    /// - Parameter spki: SubjectPublicKeyInfo DER (what the server returns, base64-decoded).
    public init(spki: Data) throws(CryptoError) {
        guard let pkcs1 = Self.pkcs1(fromSPKI: spki) else { throw .malformedEncString }
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, nil) else { throw .malformedEncString }
        self.key = key
        self.spki = spki
    }

    /// RSA-OAEP-SHA1, as an EncString of type 4 (`4.<base64>`).
    public func encrypt(_ data: Data) throws(CryptoError) -> String {
        var error: Unmanaged<CFError>?
        guard let out = SecKeyCreateEncryptedData(key, .rsaEncryptionOAEPSHA1, data as CFData, &error) as Data? else {
            throw .malformedEncString
        }
        return "4." + out.base64EncodedString()
    }

    // MARK: DER

    /// SEQUENCE { SEQUENCE { OID rsaEncryption, NULL }, BIT STRING { 0, RSAPublicKey } }.
    static func spki(fromPKCS1 pkcs1: Data) -> Data {
        let algorithm: [UInt8] = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
        let bitString = der(tag: 0x03, [0x00] + Array(pkcs1))
        return Data(der(tag: 0x30, algorithm + bitString))
    }

    static func pkcs1(fromSPKI spki: Data) -> Data? {
        let b = Array(spki)
        var i = 0
        func header(_ tag: UInt8) -> Int? {
            guard i < b.count, b[i] == tag else { return nil }
            i += 1
            guard i < b.count else { return nil }
            var len = Int(b[i]); i += 1
            if len & 0x80 != 0 {
                let n = len & 0x7F
                guard n <= 4, i + n <= b.count else { return nil }
                len = 0
                for _ in 0..<n { len = (len << 8) | Int(b[i]); i += 1 }
            }
            return i + len <= b.count ? len : nil
        }
        guard header(0x30) != nil, let algLen = header(0x30) else { return nil }
        i += algLen
        guard let bitLen = header(0x03), bitLen > 1, b[i] == 0 else { return nil }
        return Data(b[(i + 1)..<(i + bitLen)])
    }

    static func der(tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        let n = content.count
        let length: [UInt8]
        if n < 0x80 { length = [UInt8(n)] }
        else if n <= 0xFF { length = [0x81, UInt8(n)] }
        else if n <= 0xFFFF { length = [0x82, UInt8(n >> 8), UInt8(n & 0xFF)] }
        else { length = [0x83, UInt8(n >> 16), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)] }
        return [tag] + length + content
    }
}

/// Bitwarden's account fingerprint phrase: five EFF words from HKDF-Expand(SHA-256(public key), user id). Compared
/// out loud with someone before trusting their key (emergency access, organizations, signing in on a new device).
public enum Fingerprint {
    public static func phrase(publicKeySPKI: Data, material: String) -> [String] {
        let prk = SymmetricKey(data: SHA256.hash(data: publicKeySPKI))
        let expanded = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: Data(material.utf8), outputByteCount: 32)
        return words(from: expanded.withUnsafeBytes { Array($0) })
    }

    /// The hash as one big-endian number, taken apart in base 7,776 (one EFF word per digit, least significant first).
    static func words(from hash: [UInt8], count: Int = 5) -> [String] {
        let list = PassphraseGenerator.wordList
        guard !list.isEmpty else { return [] }
        var number = hash
        var out: [String] = []
        for _ in 0..<count {
            var remainder = 0
            var quotient: [UInt8] = []
            for byte in number {
                let value = remainder * 256 + Int(byte)
                let digit = value / list.count
                remainder = value % list.count
                if !quotient.isEmpty || digit != 0 { quotient.append(UInt8(digit)) }
            }
            out.append(list[remainder])
            number = quotient
        }
        return out
    }
}
