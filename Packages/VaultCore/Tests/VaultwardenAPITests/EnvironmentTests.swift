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

    @Test func messagePackFraming() {
        #expect(!LiveSync.containsChange(LiveSync.pingFrame))
        #expect(!LiveSync.containsChange(LiveSync.pingFrame + LiveSync.pingFrame))
        #expect(LiveSync.containsChange(LiveSync.pingFrame + Data([0x03, 0x93, 0x01, 0x80])))
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

@Suite struct PwnedPasswordsTests {
    @Test func parsesAndIgnoresPadding() {
        let counts = PwnedPasswords.parse("0018A45C4D1DEF81644B54AB7F969B88D65:10\r\n00D4F6E8FA6EECAD2A3AA415EEC418D38EC:0\n")
        #expect(counts == ["0018A45C4D1DEF81644B54AB7F969B88D65": 10])
    }

    /// Live call to api.pwnedpasswords.com (sends only 5-char hash prefixes).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CHIIKAWARDEN_NETWORK_TESTS"] != nil))
    func knownBreachedPassword() async throws {
        let random = UUID().uuidString + UUID().uuidString
        let result = try await PwnedPasswords.check(["password", random])
        #expect((result["password"] ?? 0) > 1000)
        #expect(result[random] == 0)
    }
}
