import CommonCrypto
import Foundation

/// Key-derivation settings returned by the server's prelogin endpoint.
public enum KDFConfig: Sendable, Equatable {
    case pbkdf2(iterations: Int)
    case argon2id(iterations: Int, memoryMiB: Int, parallelism: Int)

    // Bounds guard against a malicious or misconfigured server downgrading the KDF.
    static let pbkdf2Iterations = 600_000...2_000_000
    static let argon2Iterations = 2...10
    static let argon2MemoryMiB = 16...1024
    static let argon2Parallelism = 1...16

    public func validate() throws(CryptoError) {
        switch self {
        case .pbkdf2(let iterations):
            guard Self.pbkdf2Iterations.contains(iterations) else {
                throw .kdfOutOfBounds("PBKDF2 iterations \(iterations)")
            }
        case .argon2id(let iterations, let memory, let parallelism):
            guard Self.argon2Iterations.contains(iterations),
                  Self.argon2MemoryMiB.contains(memory),
                  Self.argon2Parallelism.contains(parallelism)
            else {
                throw .kdfOutOfBounds("Argon2id t=\(iterations) m=\(memory)MiB p=\(parallelism)")
            }
        }
    }
}

public enum KDF {
    /// Derives the 32-byte master key from the master password and account email.
    public static func masterKey(password: String, email: String, config: KDFConfig) throws(CryptoError) -> Data {
        try config.validate()
        let salt = Data(normalizedEmail(email).utf8)
        switch config {
        case .pbkdf2(let iterations):
            return try pbkdf2SHA256(password: Data(password.utf8), salt: salt, iterations: iterations, length: 32)
        case .argon2id:
            // TODO(M0): wire the reference Argon2 implementation (vendored C target).
            throw .unsupported("Argon2id is not implemented yet")
        }
    }

    /// The hash sent to the server as the login secret: PBKDF2(masterKey, password, 1).
    public static func masterPasswordHash(masterKey: Data, password: String) throws(CryptoError) -> String {
        try pbkdf2SHA256(password: masterKey, salt: Data(password.utf8), iterations: 1, length: 32)
            .base64EncodedString()
    }

    public static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, length: Int) throws(CryptoError) -> Data {
        var derived = Data(count: length)
        let status = derived.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { pw in
                salt.withUnsafeBytes { s in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pw.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                        s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        out.baseAddress?.assumingMemoryBound(to: UInt8.self), length
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw .commonCrypto(status) }
        return derived
    }
}
