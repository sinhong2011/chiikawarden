import ChiikawaCrypto
import Foundation

public struct PreloginResponse: Decodable, Sendable {
    public let kdf: Int
    public let kdfIterations: Int
    public let kdfMemory: Int?
    public let kdfParallelism: Int?

    public func config() throws(APIError) -> KDFConfig {
        switch kdf {
        case 0: return .pbkdf2(iterations: kdfIterations)
        case 1: return .argon2id(iterations: kdfIterations, memoryMiB: kdfMemory ?? 0, parallelism: kdfParallelism ?? 0)
        default: throw .unsupportedKDF(kdf)
        }
    }
}

public struct TokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    /// The user key, encrypted with the stretched master key.
    public let key: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case key
    }
}

/// Error body of a failed `connect/token` call; 2FA challenges arrive this way.
public struct TokenErrorResponse: Decodable, Sendable {
    public let error: String?
    public let errorDescription: String?
    public let twoFactorProviders: [String]?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case twoFactorProviders
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        errorDescription = try c.decodeIfPresent(String.self, forKey: .errorDescription)
        // Provider ids arrive as strings or ints depending on server version.
        if let ints = try? c.decodeIfPresent([Int].self, forKey: .twoFactorProviders) {
            twoFactorProviders = ints.map(String.init)
        } else {
            twoFactorProviders = try c.decodeIfPresent([String].self, forKey: .twoFactorProviders)
        }
    }
}

public struct SyncResponse: Decodable, Sendable {
    public let profile: Profile
    public let ciphers: [Cipher]

    public struct Profile: Decodable, Sendable {
        public let id: String
        public let email: String
        public let key: String
    }

    public struct Cipher: Decodable, Sendable, Identifiable {
        public let id: String
        public let type: Int
        public let organizationId: String?
        public let name: String
        public let login: Login?
        public let favorite: Bool?
        public let deletedDate: String?
    }

    public struct Login: Decodable, Sendable {
        public let username: String?
        public let password: String?
        public let totp: String?
        public let uris: [URI]?
    }

    public struct URI: Decodable, Sendable {
        public let uri: String?
    }
}

public enum APIError: Error, Sendable, Equatable {
    case invalidServerURL
    case http(status: Int, message: String?)
    case twoFactorRequired(providers: [String])
    case unsupportedKDF(Int)
    case missingUserKey
    case crypto(CryptoError)
}
