import CryptoKit
import Foundation

/// A 64-byte AES-256-CBC + HMAC-SHA256 key pair, the shape of Bitwarden user and org keys.
public struct SymmetricKeyPair: Sendable, Equatable {
    public let encryptionKey: Data
    public let macKey: Data

    public init(encryptionKey: Data, macKey: Data) throws(CryptoError) {
        guard encryptionKey.count == 32 else { throw .invalidKeyLength(encryptionKey.count) }
        guard macKey.count == 32 else { throw .invalidKeyLength(macKey.count) }
        self.encryptionKey = encryptionKey
        self.macKey = macKey
    }

    public init(combined: Data) throws(CryptoError) {
        guard combined.count == 64 else { throw .invalidKeyLength(combined.count) }
        try self.init(encryptionKey: combined.prefix(32), macKey: combined.suffix(32))
    }

    /// Stretches a 32-byte master key with HKDF-Expand ("enc" / "mac"), as Bitwarden clients do.
    public static func stretched(masterKey: Data) throws(CryptoError) -> SymmetricKeyPair {
        guard masterKey.count == 32 else { throw .invalidKeyLength(masterKey.count) }
        let prk = SymmetricKey(data: masterKey)
        func expand(_ info: String) -> Data {
            HKDF<SHA256>.expand(pseudoRandomKey: prk, info: Data(info.utf8), outputByteCount: 32)
                .withUnsafeBytes { Data($0) }
        }
        return try SymmetricKeyPair(encryptionKey: expand("enc"), macKey: expand("mac"))
    }
}
