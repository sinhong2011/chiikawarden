import ChiikawaCrypto
import Foundation
import Testing
@testable import VaultwardenAPI

/// Drives the whole OIDC flow headlessly against the dev stack's dex + SSO-enabled Vaultwarden
/// (`DevServer/compose.yml`): browser redirects and dex's password form are played with URLSession.
@Suite struct SSOTests {
    static var ip: String? { ProcessInfo.processInfo.environment["CHIIKAWARDEN_DEV_IP"] }

    /// Follows redirects like a browser but stops at the `bitwarden://` callback.
    final class Browser: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        var callback: URL?
        lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            if request.url?.scheme == "bitwarden" { callback = request.url; return nil }
            return request
        }
    }

    @Test func ssoThenMasterPassword() async throws {
        guard let ip = Self.ip else { return } // set CHIIKAWARDEN_DEV_IP to run
        let client = VaultClient(environment: .selfHosted(URL(string: "http://\(ip):18881")!), deviceIdentifier: UUID().uuidString)
        let start = try await client.beginSSO(identifier: "chiikawarden")
        #expect(start.authorizeURL.absoluteString.contains("code_challenge_method=S256"))

        let browser = Browser()
        // Authorize → Vaultwarden → dex login page (local connector form).
        let (pageData, pageResponse) = try await browser.session.data(from: start.authorizeURL)
        let page = String(decoding: pageData, as: UTF8.self)
        var loginURL = try #require(pageResponse.url)
        if let range = page.range(of: #"href="(/dex/auth/local[^"]*)""#, options: .regularExpression) {
            let path = String(page[range]).dropFirst(6).dropLast().replacingOccurrences(of: "&amp;", with: "&")
            loginURL = URL(string: path, relativeTo: loginURL)!.absoluteURL
            _ = try await browser.session.data(from: loginURL)
        }
        let action = page.range(of: #"action="([^"]*)""#, options: .regularExpression).map {
            String(page[$0]).dropFirst(8).dropLast().replacingOccurrences(of: "&amp;", with: "&")
        }
        var post = URLRequest(url: action.flatMap { URL(string: $0, relativeTo: loginURL)?.absoluteURL } ?? loginURL)
        post.httpMethod = "POST"
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        post.httpBody = Data("login=usagi%40chiikawarden.test&password=chiikawa-dev-password".utf8)
        _ = try? await browser.session.data(for: post)
        let callback = try #require(browser.callback, "no bitwarden:// callback")

        let session = try await client.finishSSO(callback: callback, start: start)
        #expect(session.email == "usagi@chiikawarden.test" && session.refreshToken != nil)
        #expect(throws: APIError.self) { try client.unlockSSO(session, password: "wrong") }
        let userKey = try client.unlockSSO(session, password: "chiikawa-dev-password")
        let names = try await client.sync().ciphers.compactMap { try? EncString($0.name).decryptString(with: userKey) }
        #expect(names.contains("GitHub"))

        // A forged callback is refused.
        await #expect(throws: APIError.self) {
            _ = try await client.finishSSO(callback: URL(string: "bitwarden://sso-callback?code=x&state=nope")!, start: start)
        }
    }
}
