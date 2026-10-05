import CryptoKit
import Foundation
import Security

/// An unencrypted OpenSSH private key (`-----BEGIN OPENSSH PRIVATE KEY-----`, as Bitwarden stores them)
/// that can sign agent requests. Supports Ed25519, ECDSA P-256/384/521 and RSA.
public struct SSHPrivateKey: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case notOpenSSH, encrypted, unsupported(String), malformed
    }

    enum Material: @unchecked Sendable {
        case ed25519(Curve25519.Signing.PrivateKey)
        case p256(P256.Signing.PrivateKey)
        case p384(P384.Signing.PrivateKey)
        case p521(P521.Signing.PrivateKey)
        case rsa(SecKey)
    }

    /// Wire-format public key (what `ssh-add -L` prints, base64-decoded).
    public let publicBlob: Data
    public let type: String
    public let comment: String
    let material: Material

    public init(pem: String) throws(Failure) {
        let body = pem.split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard pem.contains("BEGIN OPENSSH PRIVATE KEY"), let raw = Data(base64Encoded: String(body)) else { throw .notOpenSSH }
        let magic = Data("openssh-key-v1\0".utf8)
        guard raw.starts(with: magic) else { throw .notOpenSSH }
        do {
            var r = SSHReader(raw.dropFirst(magic.count))
            let cipher = try r.text(), kdf = try r.text()
            _ = try r.string() // kdf options
            guard cipher == "none", kdf == "none" else { throw Failure.encrypted }
            guard try r.uint32() == 1 else { throw Failure.unsupported("multiple keys") }
            publicBlob = try r.string()
            var p = SSHReader(try r.string())
            guard try p.uint32() == p.uint32() else { throw Failure.malformed } // check ints
            type = try p.text()
            switch type {
            case "ssh-ed25519":
                _ = try p.string()
                let secret = try p.string()
                material = .ed25519(try Curve25519.Signing.PrivateKey(rawRepresentation: secret.prefix(32)))
            case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
                _ = try p.string(); _ = try p.string()
                let d = try p.mpint()
                switch type {
                case "ecdsa-sha2-nistp256": material = .p256(try P256.Signing.PrivateKey(rawRepresentation: Self.pad(d, 32)))
                case "ecdsa-sha2-nistp384": material = .p384(try P384.Signing.PrivateKey(rawRepresentation: Self.pad(d, 48)))
                default: material = .p521(try P521.Signing.PrivateKey(rawRepresentation: Self.pad(d, 66)))
                }
            case "ssh-rsa":
                let n = try p.mpint(), e = try p.mpint(), d = try p.mpint(), iqmp = try p.mpint(), pp = try p.mpint(), q = try p.mpint()
                material = .rsa(try Self.rsaKey(n: n, e: e, d: d, p: pp, q: q, iqmp: iqmp))
            default:
                throw Failure.unsupported(type)
            }
            comment = (try? p.text()) ?? ""
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .malformed
        }
    }

    /// `SSH_AGENT_RSA_SHA2_256` / `_512` from the sign request.
    public struct SignFlags: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let rsaSHA256 = SignFlags(rawValue: 2)
        public static let rsaSHA512 = SignFlags(rawValue: 4)
    }

    /// Returns the wire-format signature blob for `data`.
    public func sign(_ data: Data, flags: SignFlags = []) throws -> Data {
        var w = SSHWriter()
        switch material {
        case .ed25519(let k):
            w.string(type); w.string(try k.signature(for: data))
        case .p256(let k):
            w.string(type); w.string(Self.ecdsaBlob(try k.signature(for: data).rawRepresentation))
        case .p384(let k):
            w.string(type); w.string(Self.ecdsaBlob(try k.signature(for: data).rawRepresentation))
        case .p521(let k):
            w.string(type); w.string(Self.ecdsaBlob(try k.signature(for: data).rawRepresentation))
        case .rsa(let k):
            let (name, algorithm): (String, SecKeyAlgorithm) =
                flags.contains(.rsaSHA512) ? ("rsa-sha2-512", .rsaSignatureMessagePKCS1v15SHA512)
                : flags.contains(.rsaSHA256) ? ("rsa-sha2-256", .rsaSignatureMessagePKCS1v15SHA256)
                : ("ssh-rsa", .rsaSignatureMessagePKCS1v15SHA1)
            var error: Unmanaged<CFError>?
            guard let sig = SecKeyCreateSignature(k, algorithm, data as CFData, &error) as Data? else {
                throw error!.takeRetainedValue() as Error
            }
            w.string(name); w.string(sig)
        }
        return w.data
    }

    /// `ssh-ed25519 AAAA… comment`
    public var authorizedKey: String {
        [type, publicBlob.base64EncodedString(), comment].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public var fingerprint: String {
        "SHA256:" + Data(SHA256.hash(data: publicBlob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    // MARK: Helpers

    private static func pad(_ d: Data, _ n: Int) -> Data { d.count >= n ? d.suffix(n) : Data(count: n - d.count) + d }

    private static func ecdsaBlob(_ raw: Data) -> Data {
        var w = SSHWriter()
        w.mpint(raw.prefix(raw.count / 2)); w.mpint(raw.suffix(raw.count / 2))
        return w.data
    }

    private static func rsaKey(n: Data, e: Data, d: Data, p: Data, q: Data, iqmp: Data) throws -> SecKey {
        func integer(_ m: Data) -> Data {
            var v = Data(m.drop { $0 == 0 })
            if v.isEmpty || v[v.startIndex] & 0x80 != 0 { v.insert(0, at: 0) }
            return der(0x02, v)
        }
        let dp = BigMod.mod(d, BigMod.minusOne(p)), dq = BigMod.mod(d, BigMod.minusOne(q))
        let body = [Data([0x02, 0x01, 0x00]), integer(n), integer(e), integer(d), integer(p), integer(q),
                    integer(dp), integer(dq), integer(iqmp)].reduce(Data(), +)
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        guard let key = SecKeyCreateWithData(der(0x30, body) as CFData, attributes as CFDictionary, &error) else { throw Failure.malformed }
        return key
    }

    private static func der(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        let n = content.count
        if n < 0x80 { out.append(UInt8(n)) } else {
            let len = withUnsafeBytes(of: UInt32(n).bigEndian) { Data($0) }.drop { $0 == 0 }
            out.append(0x80 | UInt8(len.count)); out.append(contentsOf: len)
        }
        return out + content
    }
}
