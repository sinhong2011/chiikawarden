import ChiikawaCrypto
import Foundation

/// Minimal Bitwarden-protocol client (Vaultwarden or the official cloud): prelogin, password login, sync.
public actor VaultClient {
    public nonisolated let environment: ServerEnvironment
    private let session: URLSession
    private let deviceIdentifier: String
    private let extraHeaders: [String: String]
    private var accessToken: String?
    private var refreshToken: String?

    /// Identifies us to the server. The official cloud gates features on known client names.
    static let clientName = "desktop"
    static let clientVersion = "2026.9.0"

    /// - Parameter extraHeaders: sent on every request, e.g. Cloudflare Access service tokens.
    public init(environment: ServerEnvironment, deviceIdentifier: String, extraHeaders: [String: String] = [:],
                session: URLSession = .shared) {
        self.environment = environment
        self.deviceIdentifier = deviceIdentifier
        self.extraHeaders = extraHeaders
        self.session = session
    }

    // MARK: Login

    public func prelogin(email: String) async throws(APIError) -> PreloginResponse {
        let body = try json(["email": KDF.normalizedEmail(email)])
        // Newest servers: identity/accounts/prelogin/password. Cloud and recent Vaultwarden:
        // identity/accounts/prelogin. Older Vaultwarden only has api/accounts/prelogin.
        let candidates = [
            (environment.identityURL, "accounts/prelogin/password"),
            (environment.identityURL, "accounts/prelogin"),
            (environment.apiURL, "accounts/prelogin"),
        ]
        var lastError = APIError.invalidServerURL
        for (base, path) in candidates {
            do {
                return try await send(post(base, path, jsonBody: body))
            } catch .http(let status, let message) where status == 404 || status == 405 {
                lastError = .http(status: status, message: message)
            }
        }
        throw lastError
    }

    /// Everything needed to unlock later without the network (all of it is safe at rest except `refreshToken`,
    /// which belongs in the Keychain).
    public struct LoginResult: Sendable {
        public let userKey: SymmetricKeyPair
        public let protectedUserKey: String
        public let kdf: KDFConfig
        public let refreshToken: String?
    }

    /// Restores a session from a stored refresh token (no password needed).
    public func restore(refreshToken: String) { self.refreshToken = refreshToken }

    /// Exchanges the refresh token for a new access token. Returns the (possibly rotated) refresh token.
    @discardableResult
    public func refreshAccessToken() async throws(APIError) -> String {
        guard let refreshToken else { throw .http(status: 401, message: "No session") }
        let token: TokenResponse = try await send(post(environment.identityURL, "connect/token", formBody: [
            "grant_type": "refresh_token", "client_id": Self.clientName, "refresh_token": refreshToken,
        ]))
        accessToken = token.accessToken
        if let rotated = token.refreshToken { self.refreshToken = rotated }
        return self.refreshToken ?? refreshToken
    }

    /// Logs in and returns the decrypted user key.
    ///
    /// - Parameters:
    ///   - twoFactor: provider id ("0" = authenticator app) and code, after a `.twoFactorRequired` error.
    ///   - newDeviceOTP: emailed code, after a `.newDeviceVerificationRequired` error (official cloud).
    public func login(email: String, password: String,
                      twoFactor: (provider: String, token: String)? = nil,
                      newDeviceOTP: String? = nil) async throws(APIError) -> SymmetricKeyPair {
        try await loginDetailed(email: email, password: password, twoFactor: twoFactor, newDeviceOTP: newDeviceOTP).userKey
    }

    public func loginDetailed(email: String, password: String,
                              twoFactor: (provider: String, token: String)? = nil,
                              newDeviceOTP: String? = nil) async throws(APIError) -> LoginResult {
        let config = try await prelogin(email: email).config()
        do {
            let masterKey = try KDF.masterKey(password: password, email: email, config: config)
            var form = [
                "grant_type": "password",
                "username": KDF.normalizedEmail(email),
                "password": try KDF.masterPasswordHash(masterKey: masterKey, password: password),
                "scope": "api offline_access",
                "client_id": Self.clientName,
                "deviceType": "7", // macOS desktop
                "deviceIdentifier": deviceIdentifier,
                "deviceName": "chiikawarden",
            ]
            if let twoFactor {
                form["twoFactorProvider"] = twoFactor.provider
                form["twoFactorToken"] = twoFactor.token
                form["twoFactorRemember"] = "0"
            }
            if let newDeviceOTP { form["newDeviceOtp"] = newDeviceOTP }
            var request = try post(environment.identityURL, "connect/token", formBody: form)
            // The cloud requires the login email echoed as base64url.
            request.setValue(Data(KDF.normalizedEmail(email).utf8).base64URLEncoded, forHTTPHeaderField: "Auth-Email")
            let token: TokenResponse = try await send(request)
            accessToken = token.accessToken
            refreshToken = token.refreshToken
            guard let protected = token.key else { throw APIError.missingUserKey }
            let stretched = try SymmetricKeyPair.stretched(masterKey: masterKey)
            let userKey = try SymmetricKeyPair(combined: EncString(protected).decrypt(with: stretched))
            return LoginResult(userKey: userKey, protectedUserKey: protected, kdf: config, refreshToken: token.refreshToken)
        } catch let error as CryptoError {
            throw .crypto(error)
        } catch let error as APIError {
            throw error
        } catch {
            throw .http(status: -1, message: error.localizedDescription)
        }
    }

    /// Current bearer token (for the notifications hub).
    public var currentAccessToken: String? { accessToken }

    /// Creates a folder (name must already be encrypted) and returns its id. Used by tests to trigger
    /// a server-side change notification.
    public func createFolder(encryptedName: String) async throws(APIError) -> String {
        struct Folder: Decodable { let id: String }
        var r = try post(environment.apiURL, "folders", jsonBody: json(["name": encryptedName]))
        if let accessToken { r.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let folder: Folder = try await send(r)
        return folder.id
    }

    public func deleteFolder(id: String) async throws(APIError) {
        var r = try request(environment.apiURL, "folders/\(id)")
        r.httpMethod = "DELETE"
        if let accessToken { r.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        _ = try await sendRaw(r)
    }

    // MARK: Item writes

    private func authorized(_ r: URLRequest) -> URLRequest {
        var r = r
        if let accessToken { r.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        return r
    }

    /// Creates a personal item from `CipherEditor.newCipher`. Returns the new id.
    public func createCipher(_ body: Data) async throws(APIError) -> String {
        struct Created: Decodable { let id: String }
        let created: Created = try await send(authorized(post(environment.apiURL, "ciphers", jsonBody: body)))
        return created.id
    }

    /// Replaces an item with a body from `CipherEditor.updatedCipher`.
    public func updateCipher(id: String, _ body: Data) async throws(APIError) {
        var r = try post(environment.apiURL, "ciphers/\(id)", jsonBody: body)
        r.httpMethod = "PUT"
        _ = try await sendRaw(authorized(r))
    }

    /// Moves to Trash (restorable).
    public func trashCipher(id: String) async throws(APIError) {
        var r = try request(environment.apiURL, "ciphers/\(id)/delete")
        r.httpMethod = "PUT"
        _ = try await sendRaw(authorized(r))
    }

    public func restoreCipher(id: String) async throws(APIError) {
        var r = try request(environment.apiURL, "ciphers/\(id)/restore")
        r.httpMethod = "PUT"
        _ = try await sendRaw(authorized(r))
    }

    /// Permanently deletes.
    public func deleteCipher(id: String) async throws(APIError) {
        var r = try request(environment.apiURL, "ciphers/\(id)")
        r.httpMethod = "DELETE"
        _ = try await sendRaw(authorized(r))
    }

    // MARK: Password hint

    /// Asks the server to email the master password hint. Vaultwarden without mail configured may
    /// return the hint directly; that hint is returned here, otherwise `nil` (sent by email).
    public func requestPasswordHint(email: String) async throws(APIError) -> String? {
        let body = try json(["email": KDF.normalizedEmail(email)])
        do {
            let _: EmptyResponse = try await send(post(environment.apiURL, "accounts/password-hint", jsonBody: body))
            return nil
        } catch .http(_, let message?) where message.hasPrefix("Your password hint is: ") {
            return String(message.dropFirst("Your password hint is: ".count))
        }
    }

    // MARK: Server

    public func config() async throws(APIError) -> ServerConfig {
        try await send(request(environment.apiURL, "config"))
    }

    // MARK: Sync

    public func sync() async throws(APIError) -> SyncResponse {
        try SyncResponse.decode(await syncData())
    }

    /// Raw sync payload — every secret in it is already encrypted, so it can be cached as-is.
    public func syncData() async throws(APIError) -> Data {
        var request = try request(environment.apiURL, "sync?excludeDomains=true")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        return try await sendRaw(request)
    }

    // MARK: Plumbing

    private func request(_ base: URL, _ path: String) throws(APIError) -> URLRequest {
        guard let url = URL(string: path, relativeTo: base.appendingSlash) else { throw .invalidServerURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.clientName, forHTTPHeaderField: "Bitwarden-Client-Name")
        request.setValue(Self.clientVersion, forHTTPHeaderField: "Bitwarden-Client-Version")
        request.setValue("7", forHTTPHeaderField: "Device-Type")
        request.setValue("Chiikawarden/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        return request
    }

    private func post(_ base: URL, _ path: String, jsonBody: Data) throws(APIError) -> URLRequest {
        var r = try request(base, path)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = jsonBody
        return r
    }

    private func post(_ base: URL, _ path: String, formBody: [String: String]) throws(APIError) -> URLRequest {
        var r = try request(base, path)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // RFC 3986 unreserved set only — `.alphanumerics` would let non-ASCII letters through unencoded.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        r.httpBody = formBody
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        return r
    }

    private func json(_ object: [String: String]) throws(APIError) -> Data {
        do { return try JSONEncoder().encode(object) } catch { throw .http(status: -1, message: "encode") }
    }

    private func sendRaw(_ request: URLRequest) async throws(APIError) -> Data {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch {
            throw .http(status: -1, message: error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw APIError.from(status: status, body: data, decoder: .vaultwarden) }
        return data
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws(APIError) -> T {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch {
            throw .http(status: -1, message: error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let decoder = JSONDecoder.vaultwarden
        guard (200..<300).contains(status) else {
            throw APIError.from(status: status, body: data, decoder: decoder)
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do { return try decoder.decode(T.self, from: data) } catch {
            throw .http(status: status, message: "Unexpected response: \(error)")
        }
    }
}

struct EmptyResponse: Decodable {}

extension APIError {
    /// Maps an error body to a typed error; login challenges arrive as 400s with distinctive fields.
    static func from(status: Int, body: Data, decoder: JSONDecoder) -> APIError {
        let err = try? decoder.decode(TokenErrorResponse.self, from: body)
        if let providers = err?.twoFactorProviders, !providers.isEmpty {
            return .twoFactorRequired(providers: providers)
        }
        let text = String(decoding: body, as: UTF8.self).lowercased()
        if text.contains("new device verification required") || text.contains("device_error") {
            return .newDeviceVerificationRequired
        }
        if text.contains("hcaptcha_sitekey") || text.contains("captcha required") {
            return .captchaRequired
        }
        let description = [err?.errorDescription, err?.message, err?.error].compactMap { $0 }.first { !$0.isEmpty }
        return .http(status: status, message: description)
    }
}

extension JSONDecoder {
    /// Vaultwarden returns camelCase on newer versions and PascalCase on older ones.
    static var vaultwarden: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .custom { keys in
            let key = keys.last!.stringValue
            guard let first = key.first, !key.contains("_") else { return keys.last! }
            return AnyKey(first.lowercased() + key.dropFirst())
        }
        return d
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension URL {
    var appendingSlash: URL {
        absoluteString.hasSuffix("/") ? self : URL(string: absoluteString + "/") ?? self
    }
}

