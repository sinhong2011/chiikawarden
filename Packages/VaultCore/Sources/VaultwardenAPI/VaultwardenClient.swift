import ChiikawaCrypto
import Foundation

/// Minimal client for a Vaultwarden server: prelogin, password login, sync.
public actor VaultwardenClient {
    public nonisolated let baseURL: URL
    private let session: URLSession
    private let deviceIdentifier: String
    private let extraHeaders: [String: String]
    private var accessToken: String?

    /// - Parameter extraHeaders: sent on every request, e.g. Cloudflare Access service tokens.
    public init(baseURL: URL, deviceIdentifier: String, extraHeaders: [String: String] = [:],
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.deviceIdentifier = deviceIdentifier
        self.extraHeaders = extraHeaders
        self.session = session
    }

    // MARK: Login

    public func prelogin(email: String) async throws(APIError) -> PreloginResponse {
        let body = try json(["email": KDF.normalizedEmail(email)])
        // Newer servers expose the identity route; older Vaultwarden only has /api/accounts/prelogin.
        do {
            return try await send(post("identity/accounts/prelogin/password", jsonBody: body))
        } catch .http(let status, _) where status == 404 || status == 405 {
            return try await send(post("api/accounts/prelogin", jsonBody: body))
        }
    }

    /// Logs in and returns the decrypted user key.
    public func login(email: String, password: String,
                      twoFactor: (provider: String, token: String)? = nil) async throws(APIError) -> SymmetricKeyPair {
        let config = try await prelogin(email: email).config()
        do {
            let masterKey = try KDF.masterKey(password: password, email: email, config: config)
            var form = [
                "grant_type": "password",
                "username": KDF.normalizedEmail(email),
                "password": try KDF.masterPasswordHash(masterKey: masterKey, password: password),
                "scope": "api offline_access",
                "client_id": "desktop",
                "deviceType": "7", // macOS desktop
                "deviceIdentifier": deviceIdentifier,
                "deviceName": "chiikawarden",
            ]
            if let twoFactor {
                form["twoFactorProvider"] = twoFactor.provider
                form["twoFactorToken"] = twoFactor.token
                form["twoFactorRemember"] = "0"
            }
            let token: TokenResponse = try await send(post("identity/connect/token", formBody: form))
            accessToken = token.accessToken
            guard let protected = token.key else { throw APIError.missingUserKey }
            let stretched = try SymmetricKeyPair.stretched(masterKey: masterKey)
            return try SymmetricKeyPair(combined: EncString(protected).decrypt(with: stretched))
        } catch let error as CryptoError {
            throw .crypto(error)
        } catch let error as APIError {
            throw error
        } catch {
            throw .http(status: -1, message: error.localizedDescription)
        }
    }

    // MARK: Sync

    public func sync() async throws(APIError) -> SyncResponse {
        var request = try request("api/sync?excludeDomains=true")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        return try await send(request)
    }

    // MARK: Plumbing

    private func request(_ path: String) throws(APIError) -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL.appendingSlash) else { throw .invalidServerURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("chiikawarden", forHTTPHeaderField: "Bitwarden-Client-Name")
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        return request
    }

    private func post(_ path: String, jsonBody: Data) throws(APIError) -> URLRequest {
        var r = try request(path)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = jsonBody
        return r
    }

    private func post(_ path: String, formBody: [String: String]) throws(APIError) -> URLRequest {
        var r = try request(path)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
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

    private func send<T: Decodable>(_ request: URLRequest) async throws(APIError) -> T {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch {
            throw .http(status: -1, message: error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let decoder = JSONDecoder.vaultwarden
        guard (200..<300).contains(status) else {
            let err = try? decoder.decode(TokenErrorResponse.self, from: data)
            if let providers = err?.twoFactorProviders, !providers.isEmpty {
                throw .twoFactorRequired(providers: providers)
            }
            throw .http(status: status, message: err?.errorDescription ?? err?.error)
        }
        do { return try decoder.decode(T.self, from: data) } catch {
            throw .http(status: status, message: "Unexpected response: \(error)")
        }
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
