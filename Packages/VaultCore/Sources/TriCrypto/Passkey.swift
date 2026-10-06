import CryptoKit
import Foundation

/// A WebAuthn ES256 credential in the shape Bitwarden stores it (`login.fido2Credentials`), decrypted.
/// Every client that syncs the vault can use it, so the format must match the official clients exactly:
/// `keyValue` is base64url PKCS#8, `credentialId` a GUID (or `b64.`-prefixed base64url for imported ids),
/// `userHandle` base64url, `counter` a decimal string.
public struct PasskeyCredential: Sendable, Equatable {
    public var credentialId: String
    public var keyValue: String
    public var rpId: String
    public var rpName: String?
    public var userHandle: String?
    public var userName: String?
    public var userDisplayName: String?
    public var counter: Int
    public var discoverable: Bool
    public var creationDate: Date

    public init(credentialId: String, keyValue: String, rpId: String, rpName: String? = nil, userHandle: String? = nil,
                userName: String? = nil, userDisplayName: String? = nil, counter: Int = 0, discoverable: Bool = true,
                creationDate: Date = .now) {
        self.credentialId = credentialId; self.keyValue = keyValue; self.rpId = rpId; self.rpName = rpName
        self.userHandle = userHandle; self.userName = userName; self.userDisplayName = userDisplayName
        self.counter = counter; self.discoverable = discoverable; self.creationDate = creationDate
    }

    /// The raw credential id the relying party sees.
    public var rawId: Data? { Passkey.rawCredentialID(credentialId) }
    public var rawUserHandle: Data? { userHandle.flatMap(Data.init(base64URL:)) }
}

public enum Passkey {
    /// COSE algorithm ES256 — the only one we create.
    public static let es256 = -7
    /// All-zero AAGUID: "none" attestation, no authenticator model is claimed.
    static let aaguid = Data(count: 16)

    public enum Failure: Error, Sendable { case unsupportedAlgorithm, badKey, badCredentialID }

    public struct Registration: Sendable {
        public let credential: PasskeyCredential
        public let credentialID: Data
        public let attestationObject: Data
    }

    public struct Assertion: Sendable {
        public let credentialID: Data
        public let authenticatorData: Data
        public let signature: Data
        public let userHandle: Data
        /// The counter value signed; persist it back if it changed.
        public let counter: Int
    }

    /// Creates a new discoverable ES256 passkey and its "none" attestation.
    public static func register(rpId: String, rpName: String? = nil, userName: String?, userDisplayName: String? = nil,
                                userHandle: Data, clientDataHash: Data, algorithms: [Int] = [es256]) throws -> Registration {
        guard algorithms.isEmpty || algorithms.contains(es256) else { throw Failure.unsupportedAlgorithm }
        let key = P256.Signing.PrivateKey()
        let guid = UUID()
        let credentialID = withUnsafeBytes(of: guid.uuid) { Data($0) }
        let credential = PasskeyCredential(
            credentialId: guid.uuidString.lowercased(), keyValue: key.derRepresentation.base64URLEncoded, rpId: rpId,
            rpName: rpName, userHandle: userHandle.base64URLEncoded, userName: userName, userDisplayName: userDisplayName)

        let raw = key.publicKey.rawRepresentation // x || y
        let cose = CBOR.map([
            (.int(1), .int(2)),     // kty: EC2
            (.int(3), .int(-7)),    // alg: ES256
            (.int(-1), .int(1)),    // crv: P-256
            (.int(-2), .bytes(raw.prefix(32))),
            (.int(-3), .bytes(raw.suffix(32))),
        ]).encoded
        var attested = aaguid
        attested.append(contentsOf: [UInt8(credentialID.count >> 8), UInt8(credentialID.count & 0xFF)])
        attested += credentialID + cose
        let authData = authenticatorData(rpId: rpId, flags: Flags.registration, counter: 0) + attested
        let attestation = CBOR.map([
            (.text("fmt"), .text("none")),
            (.text("attStmt"), .map([])),
            (.text("authData"), .bytes(authData)),
        ]).encoded
        _ = clientDataHash // "none" attestation signs nothing; the hash is echoed back by the system.
        return Registration(credential: credential, credentialID: credentialID, attestationObject: attestation)
    }

    /// Signs an assertion with a stored passkey.
    public static func assert(_ credential: PasskeyCredential, clientDataHash: Data) throws -> Assertion {
        guard let der = Data(base64URL: credential.keyValue),
              let key = try? P256.Signing.PrivateKey(derRepresentation: der) else { throw Failure.badKey }
        guard let id = credential.rawId else { throw Failure.badCredentialID }
        // Synced passkeys usually keep 0 (no counter); only advance one that is already counting.
        let counter = credential.counter > 0 ? credential.counter + 1 : 0
        let authData = authenticatorData(rpId: credential.rpId, flags: Flags.assertion, counter: UInt32(truncatingIfNeeded: counter))
        let signature = try key.signature(for: authData + clientDataHash).derRepresentation
        return Assertion(credentialID: id, authenticatorData: authData, signature: signature,
                         userHandle: credential.rawUserHandle ?? Data(), counter: counter)
    }

    enum Flags {
        // UP | UV | BE | BS (backup eligible + backed up: the passkey syncs through the vault).
        static let assertion: UInt8 = 0x01 | 0x04 | 0x08 | 0x10
        static let registration: UInt8 = assertion | 0x40 // + AT
    }

    static func authenticatorData(rpId: String, flags: UInt8, counter: UInt32) -> Data {
        var d = Data(SHA256.hash(data: Data(rpId.utf8)))
        d.append(flags)
        d.append(contentsOf: [UInt8(counter >> 24), UInt8(counter >> 16 & 0xFF), UInt8(counter >> 8 & 0xFF), UInt8(counter & 0xFF)])
        return d
    }

    /// Bitwarden's credential id string → the bytes the relying party knows.
    public static func rawCredentialID(_ id: String) -> Data? {
        if id.hasPrefix("b64.") { return Data(base64URL: String(id.dropFirst(4))) }
        guard let uuid = UUID(uuidString: id) else { return nil }
        return withUnsafeBytes(of: uuid.uuid) { Data($0) }
    }
}

/// Just enough deterministic CBOR (RFC 8949 §4.2.1 ordering is the caller's job) for WebAuthn.
indirect enum CBOR {
    case int(Int)
    case bytes(Data)
    case text(String)
    case map([(CBOR, CBOR)])

    var encoded: Data {
        switch self {
        case .int(let v): v >= 0 ? Self.head(0, UInt64(v)) : Self.head(1, UInt64(-1 - v))
        case .bytes(let d): Self.head(2, UInt64(d.count)) + d
        case .text(let s): Self.head(3, UInt64(s.utf8.count)) + Data(s.utf8)
        case .map(let pairs): pairs.reduce(Self.head(5, UInt64(pairs.count))) { $0 + $1.0.encoded + $1.1.encoded }
        }
    }

    private static func head(_ major: UInt8, _ n: UInt64) -> Data {
        let m = major << 5
        switch n {
        case 0..<24: return Data([m | UInt8(n)])
        case 24..<0x100: return Data([m | 24, UInt8(n)])
        case 0x100..<0x10000: return Data([m | 25, UInt8(n >> 8), UInt8(n & 0xFF)])
        default: return Data([m | 26]) + withUnsafeBytes(of: UInt32(truncatingIfNeeded: n).bigEndian) { Data($0) }
        }
    }
}

public extension Data {
    init?(base64URL s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b += String(repeating: "=", count: (4 - b.count % 4) % 4)
        self.init(base64Encoded: b)
    }

    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
