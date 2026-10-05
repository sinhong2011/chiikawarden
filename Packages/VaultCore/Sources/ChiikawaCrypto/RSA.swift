import Foundation
import Security

/// The account's RSA private key, used to unwrap organization keys (EncString type 3/4).
public struct RSAPrivateKey: @unchecked Sendable {
    let key: SecKey

    /// - Parameter pkcs8: DER-encoded PKCS#8 PrivateKeyInfo, as stored (encrypted) in the profile.
    public init(pkcs8: Data) throws(CryptoError) {
        guard let pkcs1 = Self.pkcs1(fromPKCS8: pkcs8) else { throw .malformedEncString }
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                    kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, nil) else { throw .malformedEncString }
        self.key = key
    }

    /// Decrypts `4.<b64>` (RSA-OAEP-SHA1) or `3.<b64>` (RSA-OAEP-SHA256) EncStrings.
    public func decrypt(_ encString: String) throws(CryptoError) -> Data {
        guard let dot = encString.firstIndex(of: "."), let type = Int(encString[..<dot]) else { throw .malformedEncString }
        let payload = encString[encString.index(after: dot)...].split(separator: "|").first.map(String.init) ?? ""
        guard let cipher = Data(base64Encoded: payload) else { throw .malformedEncString }
        let algorithm: SecKeyAlgorithm
        switch type {
        case 4, 6: algorithm = .rsaEncryptionOAEPSHA1
        case 3, 5: algorithm = .rsaEncryptionOAEPSHA256
        default: throw .unsupportedEncType(type)
        }
        var error: Unmanaged<CFError>?
        guard let plain = SecKeyCreateDecryptedData(key, algorithm, cipher as CFData, &error) as Data? else {
            throw .macMismatch
        }
        return plain
    }

    /// PKCS#8 PrivateKeyInfo ::= SEQUENCE { version INTEGER, algorithm SEQUENCE, privateKey OCTET STRING }.
    /// Returns the inner PKCS#1 RSAPrivateKey (the OCTET STRING contents).
    static func pkcs1(fromPKCS8 der: Data) -> Data? {
        var reader = DERReader(Array(der))
        guard reader.enter(tag: 0x30), reader.skip(tag: 0x02), reader.skip(tag: 0x30),
              let octets = reader.read(tag: 0x04) else { return nil }
        return Data(octets)
    }
}

/// Just enough DER to walk PKCS#8.
private struct DERReader {
    var bytes: [UInt8]
    var i = 0
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    private mutating func header(tag: UInt8) -> Int? {
        guard i < bytes.count, bytes[i] == tag else { return nil }
        i += 1
        guard i < bytes.count else { return nil }
        var len = Int(bytes[i]); i += 1
        if len & 0x80 != 0 {
            let n = len & 0x7f
            guard n <= 4, i + n <= bytes.count else { return nil }
            len = 0
            for _ in 0..<n { len = (len << 8) | Int(bytes[i]); i += 1 }
        }
        return i + len <= bytes.count ? len : nil
    }

    mutating func enter(tag: UInt8) -> Bool { header(tag: tag) != nil }

    mutating func skip(tag: UInt8) -> Bool {
        guard let len = header(tag: tag) else { return false }
        i += len
        return true
    }

    mutating func read(tag: UInt8) -> ArraySlice<UInt8>? {
        guard let len = header(tag: tag) else { return nil }
        defer { i += len }
        return bytes[i..<(i + len)]
    }
}
