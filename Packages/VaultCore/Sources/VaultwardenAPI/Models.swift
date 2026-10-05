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
    public let message: String?
    public let twoFactorProviders: [String]?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case message
        case twoFactorProviders
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        errorDescription = try c.decodeIfPresent(String.self, forKey: .errorDescription)
        message = try c.decodeIfPresent(String.self, forKey: .message)
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
    public let folders: [Folder]?
    public let collections: [Collection]?

    public struct Folder: Decodable, Sendable {
        public let id: String
        /// Encrypted with the user key.
        public let name: String
    }

    public struct Collection: Decodable, Sendable {
        public let id: String
        public let organizationId: String
        /// Encrypted with the organization key.
        public let name: String
    }

    /// Decodes a raw (possibly cached) sync payload.
    public static func decode(_ data: Data) throws(APIError) -> SyncResponse {
        do { return try JSONDecoder.vaultwarden.decode(SyncResponse.self, from: data) } catch {
            throw .http(status: -1, message: "Unexpected sync payload: \(error)")
        }
    }

    public struct Profile: Decodable, Sendable {
        public let id: String
        public let email: String
        public let key: String
        /// PKCS#8 RSA private key, encrypted with the user key.
        public let privateKey: String?
        public let organizations: [Organization]?
    }

    public struct Organization: Decodable, Sendable {
        public let id: String
        public let name: String?
        /// Org symmetric key, RSA-encrypted to the user's public key.
        public let key: String?
    }

    public struct Cipher: Decodable, Sendable, Identifiable {
        public let id: String
        public let type: Int
        public let organizationId: String?
        /// Optional per-item key, encrypted with the user or org key.
        public let key: String?
        public let folderId: String?
        public let collectionIds: [String]?
        public let name: String
        public let notes: String?
        public let login: Login?
        public let card: Card?
        public let identity: Identity?
        public let sshKey: SSHKey?
        public let fields: [Field]?
        public let favorite: Bool?
        public let deletedDate: String?
    }

    public struct Login: Decodable, Sendable {
        public let username: String?
        public let password: String?
        public let totp: String?
        public let uris: [URI]?
        public let fido2Credentials: [Fido2Credential]?
    }

    public struct Card: Decodable, Sendable {
        public let cardholderName: String?
        public let brand: String?
        public let number: String?
        public let expMonth: String?
        public let expYear: String?
        public let code: String?
    }

    public struct Identity: Decodable, Sendable {
        public let title: String?
        public let firstName: String?
        public let middleName: String?
        public let lastName: String?
        public let company: String?
        public let email: String?
        public let phone: String?
        public let username: String?
        public let address1: String?
        public let address2: String?
        public let city: String?
        public let state: String?
        public let postalCode: String?
        public let country: String?
        public let ssn: String?
        public let passportNumber: String?
        public let licenseNumber: String?
    }

    /// Custom field. `type`: 0 text, 1 hidden, 2 boolean, 3 linked.
    public struct Field: Decodable, Sendable {
        public let name: String?
        public let value: String?
        public let type: Int
    }

    public struct SSHKey: Decodable, Sendable {
        public let privateKey: String?
        public let publicKey: String?
        public let keyFingerprint: String?
    }

    /// Only presence matters to the UI for now.
    public struct Fido2Credential: Decodable, Sendable {}

    public struct URI: Decodable, Sendable {
        public let uri: String?
    }
}

/// `GET /api/config` — public, no auth. Used to show server health before login.
public struct ServerConfig: Decodable, Sendable, Equatable {
    public let version: String?
    public let server: Server?

    public struct Server: Decodable, Sendable, Equatable {
        public let name: String?
    }

    /// "Vaultwarden" for self-hosted Vaultwarden, otherwise "Bitwarden".
    public var productName: String { server?.name ?? "Bitwarden" }
}

public enum APIError: Error, Sendable, Equatable {
    case invalidServerURL
    case http(status: Int, message: String?)
    case twoFactorRequired(providers: [String])
    /// Official cloud: a code was emailed; retry login with `newDeviceOTP`.
    case newDeviceVerificationRequired
    /// Official cloud asked for a captcha; password login from this client can't continue.
    case captchaRequired
    case unsupportedKDF(Int)
    case missingUserKey
    case crypto(CryptoError)
}
