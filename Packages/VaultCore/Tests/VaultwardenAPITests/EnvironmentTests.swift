import Foundation
import Testing
@testable import VaultwardenAPI

@Suite struct EnvironmentTests {
    @Test func cloudEndpoints() {
        #expect(ServerEnvironment.bitwardenUS.identityURL.absoluteString == "https://identity.bitwarden.com/")
        #expect(ServerEnvironment.bitwardenEU.apiURL.absoluteString == "https://api.bitwarden.eu/")
    }

    @Test(arguments: ["https://vault.home.arpa", "https://vault.home.arpa/", "https://example.com/vw"])
    func selfHostedEndpoints(base: String) {
        let env = ServerEnvironment.selfHosted(URL(string: base)!)
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        #expect(env.apiURL.absoluteString == trimmed + "/api/")
        #expect(env.identityURL.absoluteString == trimmed + "/identity/")
    }

    @Test func challengeMapping() {
        let d = JSONDecoder.vaultwarden
        #expect(APIError.from(status: 400, body: Data(#"{"error":"invalid_grant","error_description":"New device verification required"}"#.utf8), decoder: d)
            == .newDeviceVerificationRequired)
        #expect(APIError.from(status: 400, body: Data(#"{"HCaptcha_SiteKey":"abc"}"#.utf8), decoder: d) == .captchaRequired)
        #expect(APIError.from(status: 400, body: Data(#"{"TwoFactorProviders":[0,1]}"#.utf8), decoder: d)
            == .twoFactorRequired(providers: ["0", "1"]))
    }
}
