import Foundation
import Testing
@testable import VaultwardenAPI

@Suite struct DecodingTests {
    @Test func decodesPascalCaseSync() throws {
        let json = #"""
        {"Profile":{"Id":"u1","Email":"usagi@example.com","Key":"2.a|b|c"},
         "Ciphers":[{"Id":"c1","Type":1,"OrganizationId":null,"Name":"2.x|y|z",
                     "Login":{"Username":"2.u|u|u","Password":null,"Totp":null,"Uris":[{"Uri":"2.q|q|q"}]},
                     "Favorite":true,"DeletedDate":null}]}
        """#
        let sync = try JSONDecoder.vaultwarden.decode(SyncResponse.self, from: Data(json.utf8))
        #expect(sync.profile.email == "usagi@example.com")
        #expect(sync.ciphers.first?.login?.uris?.first?.uri == "2.q|q|q")
    }

    @Test func decodesTokenAndTwoFactorChallenge() throws {
        let token = try JSONDecoder.vaultwarden.decode(TokenResponse.self, from: Data(
            #"{"access_token":"a","refresh_token":"r","expires_in":7200,"Key":"2.k|k|k"}"#.utf8))
        #expect(token.key == "2.k|k|k")
        let err = try JSONDecoder.vaultwarden.decode(TokenErrorResponse.self, from: Data(
            #"{"error":"invalid_grant","error_description":"Two factor required.","TwoFactorProviders":[0]}"#.utf8))
        #expect(err.twoFactorProviders == ["0"])
    }

    @Test func kdfMapping() throws {
        let p = try JSONDecoder.vaultwarden.decode(PreloginResponse.self, from: Data(
            #"{"Kdf":1,"KdfIterations":3,"KdfMemory":64,"KdfParallelism":4}"#.utf8))
        #expect(try p.config() == .argon2id(iterations: 3, memoryMiB: 64, parallelism: 4))
    }
}
