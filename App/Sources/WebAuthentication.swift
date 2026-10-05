import AppKit
import AuthenticationServices

/// Runs an identity provider's sign-in in a system web-authentication sheet and returns the callback URL.
/// The `bitwarden` callback scheme is caught for this session only; no URL scheme is registered.
@MainActor
enum WebAuthentication {
    enum Cancelled: Error { case byUser }

    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
        }
    }

    static func run(_ url: URL) async throws -> URL {
        let anchor = Anchor()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme("bitwarden")) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: Cancelled.byUser)
                } else {
                    continuation.resume(throwing: error ?? Cancelled.byUser)
                }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false // keep the IdP's own session (and its SSO) if any
            withExtendedLifetime(anchor) { _ = session.start() }
        }
    }
}
