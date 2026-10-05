import ChiikawaCrypto
import Foundation
import Testing
@testable import VaultwardenAPI

/// Integration tests against the seeded dev servers (see DevServer/README.md).
///
///     CHIIKAWARDEN_DEV_HOST=192.168.1.50 \
///     CHIIKAWARDEN_DEV_CA=$PWD/../../DevServer/data/root.crt swift test
enum DevServer {
    static let env = ProcessInfo.processInfo.environment
    static let host = env["CHIIKAWARDEN_DEV_HOST"]
    static let password = env["CHIIKAWARDEN_DEV_PASSWORD"] ?? "chiikawa-dev-password"
    static let totpSecret = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"
    static var enabled: Bool { host != nil }

    /// Latest Vaultwarden and a 1.30.x build, to cover older API shapes.
    static let ports = [18843, 18844]

    static func client(port: Int) throws -> VaultClient {
        let ca = try env["CHIIKAWARDEN_DEV_CA"].map { try Data(contentsOf: URL(filePath: $0)) }
        let trust = ServerTrust(certificates: ca.map { [$0] } ?? [])
        return VaultClient(environment: .selfHosted(URL(string: "https://\(host!):\(port)")!),
                                 deviceIdentifier: "6b0e4a3c-1d2e-4f50-8a6b-7c8d9e0f1a2b",
                                 session: trust.makeSession())
    }
}

@Suite(.enabled(if: DevServer.enabled, "set CHIIKAWARDEN_DEV_HOST to run"), .serialized)
struct DevServerTests {
    @Test(arguments: DevServer.ports)
    func pbkdf2LoginAndSync(port: Int) async throws {
        let client = try DevServer.client(port: port)
        let userKey = try await client.login(email: "usagi@chiikawarden.test", password: DevServer.password)
        let sync = try await client.sync()
        let names = Set(sync.ciphers.filter { $0.organizationId == nil }.compactMap {
            try? EncString($0.name).decryptString(with: userKey)
        })
        #expect(names.contains("GitHub"))
        #expect(names.contains("ちいかわ ショップ"))
    }

    @Test(arguments: DevServer.ports)
    func serverConfig(port: Int) async throws {
        let config = try await DevServer.client(port: port).config()
        #expect(config.version != nil)
    }

    @Test(arguments: DevServer.ports)
    func passwordHintRequestSucceeds(port: Int) async throws {
        // Dev servers have mail (Mailpit), so the hint is emailed rather than returned.
        _ = try await DevServer.client(port: port).requestPasswordHint(email: "usagi@chiikawarden.test")
    }

    @Test(arguments: DevServer.ports)
    func organizationItemsDecrypt(port: Int) async throws {
        let client = try DevServer.client(port: port)
        let userKey = try await client.login(email: "usagi@chiikawarden.test", password: DevServer.password)
        let sync = try await client.sync()
        let keyring = Keyring(userKey: userKey, profile: sync.profile)
        #expect(keyring.failedOrgs.isEmpty)
        let orgNames = sync.ciphers.filter { $0.organizationId != nil }.compactMap { cipher in
            keyring.key(for: cipher).flatMap { try? EncString(cipher.name).decryptString(with: $0) }
        }
        #expect(orgNames.contains("Family Netflix"))
    }

    @Test(arguments: DevServer.ports)
    func wrongPasswordIsRejected(port: Int) async throws {
        let client = try DevServer.client(port: port)
        await #expect(throws: APIError.self) {
            _ = try await client.login(email: "usagi@chiikawarden.test", password: "nope")
        }
    }

    @Test(arguments: DevServer.ports)
    func totpChallengeThenSuccess(port: Int) async throws {
        let client = try DevServer.client(port: port)
        await #expect(throws: APIError.twoFactorRequired(providers: ["0"])) {
            _ = try await client.login(email: "momonga@chiikawarden.test", password: DevServer.password)
        }
        // Vaultwarden rejects a code already used in this time step (e.g. by a test run seconds ago),
        // so fall back to the next step, which its drift window accepts.
        let totp = TOTP(DevServer.totpSecret)!
        do {
            _ = try await client.login(email: "momonga@chiikawarden.test", password: DevServer.password,
                                       twoFactor: ("0", totp.code()))
        } catch {
            _ = try await client.login(email: "momonga@chiikawarden.test", password: DevServer.password,
                                       twoFactor: ("0", totp.code(at: .now.addingTimeInterval(30))))
        }
    }

    @Test(arguments: DevServer.ports)
    func argon2idLoginAndSync(port: Int) async throws {
        let client = try DevServer.client(port: port)
        let userKey = try await client.login(email: "hachiware@chiikawarden.test", password: DevServer.password)
        let names = try await client.sync().ciphers.compactMap { try? EncString($0.name).decryptString(with: userKey) }
        #expect(names.contains("GitHub"))
    }
}
