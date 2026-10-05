import Foundation
import Security

/// Trusts the system roots plus extra CA certificates, for self-hosted servers behind a private CA.
public final class ServerTrust: NSObject, URLSessionDelegate, Sendable {
    private let anchors: [SecCertificate]

    /// - Parameter pemOrDER: CA certificates as PEM or DER data.
    public init(certificates pemOrDER: [Data]) {
        anchors = pemOrDER.compactMap(ServerTrust.certificate(from:))
    }

    public func makeSession() -> URLSession {
        URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust, !anchors.isEmpty
        else { return (.performDefaultHandling, nil) }

        SecTrustSetAnchorCertificates(trust, anchors as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, false) // keep system roots too
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
            ? (.useCredential, URLCredential(trust: trust))
            : (.cancelAuthenticationChallenge, nil)
    }

    static func certificate(from data: Data) -> SecCertificate? {
        if let der = SecCertificateCreateWithData(nil, data as CFData) { return der }
        guard let pem = String(data: data, encoding: .utf8) else { return nil }
        let body = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: body) else { return nil }
        return SecCertificateCreateWithData(nil, der as CFData)
    }
}
