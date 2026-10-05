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
        let collections = (sync.collections ?? []).compactMap { c in
            keyring.orgKeys[c.organizationId].flatMap { try? EncString(c.name).decryptString(with: $0) }
        }
        #expect(collections.contains("Shared"))
        #expect(sync.ciphers.contains { !($0.collectionIds ?? []).isEmpty })
    }

    @Test(arguments: DevServer.ports)
    func offlineUnlockAndRefreshToken(port: Int) async throws {
        // Log in once, keep only what an app stores on disk…
        let first = try await DevServer.client(port: port).loginDetailed(email: "usagi@chiikawarden.test", password: DevServer.password)
        let refresh = try #require(first.refreshToken)
        // …unlock offline: re-derive the master key and open the protected user key.
        let mk = try KDF.masterKey(password: DevServer.password, email: "usagi@chiikawarden.test", config: first.kdf)
        let userKey = try SymmetricKeyPair(combined: EncString(first.protectedUserKey).decrypt(with: .stretched(masterKey: mk)))
        #expect(userKey == first.userKey)
        // …and resume the session with a fresh client using the refresh token.
        let resumed = try DevServer.client(port: port)
        await resumed.restore(refreshToken: refresh)
        try await resumed.refreshAccessToken()
        let names = try await resumed.sync().ciphers.compactMap { try? EncString($0.name).decryptString(with: userKey) }
        #expect(names.contains("GitHub"))
    }

    @Test(arguments: [18843]) // websockets via Caddy on the latest server
    func liveSyncNotifiesOnChange(port: Int) async throws {
        let client = try DevServer.client(port: port)
        let userKey = try await client.login(email: "usagi@chiikawarden.test", password: DevServer.password)
        let token = try #require(await client.currentAccessToken)
        let ca = try DevServer.env["CHIIKAWARDEN_DEV_CA"].map { try Data(contentsOf: URL(filePath: $0)) }
        let session = ServerTrust(certificates: ca.map { [$0] } ?? []).makeSession()
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let live = LiveSync(environment: .selfHosted(URL(string: "https://\(DevServer.host!):\(port)")!),
                            accessToken: token, session: session) { continuation.yield() }
        try await live.start()
        let folder = try await client.createFolder(encryptedName: EncString.encrypt(Data("live-test".utf8), with: userKey).description)
        let notified = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in stream { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(8)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        try await client.deleteFolder(id: folder)
        await live.stop()
        #expect(notified)
    }

    @Test(arguments: DevServer.ports)
    func createEditTrashRestoreDelete(port: Int) async throws {
        let client = try DevServer.client(port: port)
        let userKey = try await client.login(email: "hachiware@chiikawarden.test", password: DevServer.password)
        func find(_ id: String) async throws -> (SyncResponse.Cipher?, Data?) {
            let data = try await client.syncData()
            return (try SyncResponse.decode(data).ciphers.first { $0.id == id }, CipherEditor.rawCiphers(fromSync: data)[id])
        }
        func name(_ c: SyncResponse.Cipher?) -> String? { c.flatMap { try? EncString($0.name).decryptString(with: userKey) } }

        // Create
        let id = try await client.createCipher(CipherEditor.newCipher(
            kind: .login, edit: CipherEdit(name: "Test ✏️", username: "a", password: "old-pass", uri: "https://example.com"), key: userKey))
        var (cipher, raw) = try await find(id)
        #expect(name(cipher) == "Test ✏️")

        // Edit: password change goes to history; untouched fields stay
        let original = try #require(raw)
        try await client.updateCipher(id: id, CipherEditor.updatedCipher(raw: original,
            edit: CipherEdit(name: "Test edited", password: "new-pass"), key: userKey))
        (cipher, raw) = try await find(id)
        #expect(name(cipher) == "Test edited")
        let pw = cipher?.login?.password.flatMap { try? EncString($0).decryptString(with: userKey) }
        #expect(pw == "new-pass")
        let user = cipher?.login?.username.flatMap { try? EncString($0).decryptString(with: userKey) }
        #expect(user == "a")
        let rawData = try #require(raw)
        let rawObject = try #require(CipherEditor.normalize(try JSONSerialization.jsonObject(with: rawData)) as? [String: Any])
        let history = rawObject["passwordHistory"] as? [[String: Any]] ?? []
        let firstHistory = (history.first?["password"] as? String).flatMap { try? EncString($0).decryptString(with: userKey) }
        #expect(firstHistory == "old-pass")

        // Trash → restore → delete forever
        try await client.trashCipher(id: id)
        (cipher, _) = try await find(id)
        #expect(cipher?.deletedDate != nil)
        try await client.restoreCipher(id: id)
        (cipher, _) = try await find(id)
        #expect(cipher?.deletedDate == nil)
        try await client.deleteCipher(id: id)
        (cipher, _) = try await find(id)
        #expect(cipher == nil)
    }

    @Test(arguments: DevServer.ports)
    func cardPropertiesAndCustomFields(port: Int) async throws {
        let client = try DevServer.client(port: port)
        let key = try await client.login(email: "hachiware@chiikawarden.test", password: DevServer.password)
        func dec(_ s: String?) -> String? { s.flatMap { try? EncString($0).decryptString(with: key) } }
        var edit = CipherEdit(name: "Test card")
        edit.properties = ["number": "4111111111111111", "cardholderName": "Hachiware", "code": "123"]
        edit.customFields = [CustomField(name: "PIN", value: "0000", kind: .hidden)]
        let id = try await client.createCipher(CipherEditor.newCipher(kind: .card, edit: edit, key: key))
        var data = try await client.syncData()
        let raw = try #require(CipherEditor.rawCiphers(fromSync: data)[id])

        var change = CipherEdit()
        change.properties = ["number": "5555444433331111"]
        change.customFields = [CustomField(name: "PIN", value: "9999", kind: .hidden), CustomField(name: "Bank", value: "Pochi", kind: .text)]
        try await client.updateCipher(id: id, CipherEditor.updatedCipher(raw: raw, edit: change, key: key))
        data = try await client.syncData()
        let cipher = try #require(try SyncResponse.decode(data).ciphers.first { $0.id == id })
        #expect(dec(cipher.card?.number) == "5555444433331111")
        #expect(dec(cipher.card?.cardholderName) == "Hachiware") // untouched property kept
        let fields = (cipher.fields ?? []).map { "\(dec($0.name) ?? "")=\(dec($0.value) ?? "")/\($0.type)" }
        #expect(fields == ["PIN=9999/1", "Bank=Pochi/0"])
        try await client.deleteCipher(id: id)
    }

    @Test(arguments: DevServer.ports)
    func passkeyRoundTrip(port: Int) async throws {
        let client = try DevServer.client(port: port)
        let key = try await client.login(email: "hachiware@chiikawarden.test", password: DevServer.password)
        let hash = Data(repeating: 7, count: 32)
        let reg = try Passkey.register(rpId: "webauthn.io", rpName: "WebAuthn.io", userName: "hachiware",
                                       userHandle: Data("hw-1".utf8), clientDataHash: hash)
        var edit = CipherEdit(name: "Passkey test", username: "hachiware", uri: "https://webauthn.io")
        edit.passkey = reg.credential
        let id = try await client.createCipher(CipherEditor.newCipher(kind: .login, edit: edit, key: key))

        var data = try await client.syncData()
        var cipher = try #require(try SyncResponse.decode(data).ciphers.first { $0.id == id })
        let stored = try #require(cipher.login?.fido2Credentials?.first?.decrypted(with: key))
        #expect(stored.credentialId == reg.credential.credentialId && stored.keyValue == reg.credential.keyValue)
        #expect(stored.rpId == "webauthn.io" && stored.userHandle == reg.credential.userHandle && stored.discoverable)
        #expect(abs(stored.creationDate.timeIntervalSince(reg.credential.creationDate)) < 1)
        let assertion = try Passkey.assert(stored, clientDataHash: hash)
        #expect(assertion.credentialID == reg.credentialID)

        // Counter update touches nothing else.
        var bump = CipherEdit()
        bump.passkeyCounter = (stored.credentialId, 5)
        let raw = try #require(CipherEditor.rawCiphers(fromSync: data)[id])
        try await client.updateCipher(id: id, CipherEditor.updatedCipher(raw: raw, edit: bump, key: key))
        data = try await client.syncData()
        cipher = try #require(try SyncResponse.decode(data).ciphers.first { $0.id == id })
        let after = try #require(cipher.login?.fido2Credentials?.first?.decrypted(with: key))
        #expect(after.counter == 5 && after.keyValue == stored.keyValue)
        #expect((try? EncString(cipher.login?.username ?? "").decryptString(with: key)) == "hachiware")
        try await client.deleteCipher(id: id)
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
