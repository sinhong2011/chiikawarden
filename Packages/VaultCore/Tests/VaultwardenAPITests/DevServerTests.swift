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

    static func client(port: Int) throws -> VaultwardenClient {
        let ca = try env["CHIIKAWARDEN_DEV_CA"].map { try Data(contentsOf: URL(filePath: $0)) }
        let trust = ServerTrust(certificates: ca.map { [$0] } ?? [])
        return VaultwardenClient(baseURL: URL(string: "https://\(host!):\(port)")!,
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
        let code = TOTP.code(secretBase32: DevServer.totpSecret)
        _ = try await client.login(email: "momonga@chiikawarden.test", password: DevServer.password,
                                   twoFactor: ("0", code))
    }

    @Test(arguments: DevServer.ports)
    func argon2AccountReportsUnsupportedForNow(port: Int) async throws {
        let client = try DevServer.client(port: port)
        await #expect(throws: APIError.crypto(.unsupported("Argon2id is not implemented yet"))) {
            _ = try await client.login(email: "hachiware@chiikawarden.test", password: DevServer.password)
        }
    }
}

/// Minimal RFC 6238 TOTP for tests (SHA-1, 6 digits, 30 s).
enum TOTP {
    static func code(secretBase32: String, date: Date = .now) -> String {
        let key = base32Decode(secretBase32)
        var counter = UInt64(date.timeIntervalSince1970 / 30).bigEndian
        let msg = Data(bytes: &counter, count: 8)
        let mac = Data(HMACSHA1.mac(key: key, message: msg))
        let o = Int(mac[mac.count - 1] & 0x0f)
        let bin = (UInt32(mac[o] & 0x7f) << 24) | (UInt32(mac[o + 1]) << 16) | (UInt32(mac[o + 2]) << 8) | UInt32(mac[o + 3])
        return String(format: "%06d", bin % 1_000_000)
    }

    static func base32Decode(_ s: String) -> Data {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = 0, value = 0
        var out = Data()
        for ch in s.uppercased() where ch != "=" {
            guard let i = alphabet.firstIndex(of: ch) else { continue }
            value = (value << 5) | i
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return out
    }
}

import CryptoKit
enum HMACSHA1 {
    static func mac(key: Data, message: Data) -> [UInt8] {
        Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }
}
