import ChiikawaCrypto
import Foundation
import Testing
@testable import VaultwardenAPI

@Suite struct ImportExportTests {
    let key = try! SymmetricKeyPair(combined: Data((0..<64).map { UInt8($0) }))
    let otherKey = try! SymmetricKeyPair(combined: Data((0..<64).map { UInt8(255 - $0) }))

    // MARK: CSV

    @Test func csvHandlesQuotesNewlinesAndCommas() {
        let text = "a,b,c\r\n\"x, y\",\"say \"\"hi\"\"\",\"line1\nline2\"\n,,\n"
        let rows = CSV.parse(text)
        #expect(rows == [["a", "b", "c"], ["x, y", "say \"hi\"", "line1\nline2"], ["", "", ""]])
        #expect(CSV.parse(CSV.write(rows)) == rows)
    }

    @Test func detectsBrowserFormats() throws {
        let chrome = "name,url,username,password,note\nGitHub,https://github.com/login,usagi,pw1,hello\n"
        let safari = "Title,URL,Username,Password,Notes,OTPAuth\nGitHub,https://github.com,usagi,pw2,,otpauth://totp/x?secret=ABC\n"
        let firefox = "\"url\",\"username\",\"password\",\"httpRealm\",\"formActionOrigin\",\"guid\"\n\"https://www.github.com\",\"usagi\",\"pw3\",,\"\",\"{1}\"\n"
        let c = try VaultImport.preview(Data(chrome.utf8))
        #expect(c.format == .chromeCSV)
        #expect(c.items.first?.name == "GitHub" && c.items.first?.json["notes"] as? String == "hello")
        let s = try VaultImport.preview(Data(safari.utf8))
        #expect(s.format == .safariCSV)
        #expect((s.items.first?.json["login"] as? [String: Any])?["totp"] as? String == "otpauth://totp/x?secret=ABC")
        let f = try VaultImport.preview(Data(firefox.utf8))
        #expect(f.format == .firefoxCSV)
        #expect(f.items.first?.name == "github.com" && f.items.first?.host == "github.com")
        #expect(throws: ImportError.unsupported) { try VaultImport.preview(Data("foo,bar\n1,2\n".utf8)) }
    }

    @Test func bitwardenCSVRoundTrip() throws {
        let folders: [[String: Any]] = [["id": "f1", "name": "Work"]]
        let items: [[String: Any]] = [
            ["type": 1, "name": "GitHub", "folderId": "f1", "favorite": true, "notes": "a, \"b\"\nc",
             "fields": [["name": "PIN", "value": "0420", "type": 1]],
             "login": ["username": "usagi", "password": "p,w\"1", "totp": "JBSW", "uris": [["uri": "https://github.com"]]]],
            ["type": 2, "name": "Note", "notes": "secret"],
            ["type": 3, "name": "Card"],
        ]
        let (data, skipped) = VaultExport.csv(folders: folders, items: items)
        #expect(skipped == 1)
        let preview = try VaultImport.preview(data)
        #expect(preview.format == .bitwardenCSV)
        #expect(preview.folders == ["Work"])
        let login = try #require(preview.items.first)
        #expect(login.folder == 0 && login.json["favorite"] as? Bool == true && login.json["notes"] as? String == "a, \"b\"\nc")
        let l = login.json["login"] as? [String: Any]
        #expect(l?["password"] as? String == "p,w\"1" && l?["totp"] as? String == "JBSW")
        #expect((login.json["fields"] as? [[String: Any]])?.first?["value"] as? String == "0420")
        #expect(preview.items[1].type == 2 && preview.items[1].json["notes"] as? String == "secret")
    }

    // MARK: Bitwarden JSON

    func sampleJSON() throws -> Data {
        try VaultExport.json(folders: [["id": "f1", "name": "Work"]], items: [
            ["id": "i1", "type": 1, "name": "GitHub", "folderId": "f1", "favorite": false, "reprompt": 0,
             "login": ["username": "usagi", "password": "m7Kq#vR2", "uris": [["uri": "https://github.com", "match": NSNull()]]]],
            ["id": "i2", "type": 5, "name": "homelab", "sshKey": ["privateKey": "-----BEGIN…", "publicKey": "ssh-ed25519 AAA", "keyFingerprint": "SHA256:x"]],
        ])
    }

    @Test func passwordProtectedExportRoundTrip() throws {
        let file = try VaultExport.passwordProtected(sampleJSON(), password: "file-pass", kdf: .pbkdf2(iterations: 600_000))
        #expect(throws: ImportError.passwordRequired) { try VaultImport.preview(file) }
        #expect(throws: ImportError.wrongPassword) { try VaultImport.preview(file, password: "nope") }
        let preview = try VaultImport.preview(file, password: "file-pass")
        #expect(preview.format == .bitwardenPasswordProtected)
        #expect(preview.folders == ["Work"])
        #expect(preview.items.map(\.name) == ["GitHub", "homelab"])
        #expect(preview.items[0].folder == 0 && preview.items[0].username == "usagi" && preview.items[0].host == "github.com")
        #expect((preview.items[1].json["sshKey"] as? [String: Any])?["publicKey"] as? String == "ssh-ed25519 AAA")
        // Plain parts of the file never contain the vault.
        #expect(!String(decoding: file, as: UTF8.self).contains("GitHub"))
        // For the independent check: `python3 DevServer/verify_export.py <file> file-pass`.
        if let out = ProcessInfo.processInfo.environment["CHIIKAWARDEN_EXPORT_OUT"] {
            try file.write(to: URL(fileURLWithPath: out))
        }
    }

    @Test func accountEncryptedExportNeedsTheSameAccount() throws {
        let item = try CipherFields.encrypt(["type": 2, "name": "Note", "notes": "secret", "secureNote": ["type": 0]], key: key)
        let doc: [String: Any] = [
            "encrypted": true,
            "encKeyValidation_DO_NOT_EDIT": try EncString.encrypt(Data("check".utf8), with: key).description,
            "folders": [], "items": [item],
        ]
        let data = try JSONSerialization.data(withJSONObject: doc)
        #expect(throws: ImportError.otherAccount) { try VaultImport.preview(data, accountKey: otherKey) }
        let preview = try VaultImport.preview(data, accountKey: key)
        #expect(preview.format == .bitwardenAccountEncrypted && preview.items.first?.json["notes"] as? String == "secret")
    }

    // MARK: Full path

    /// A synced (encrypted) vault → plain export → import request → decrypted back: the same values.
    @Test func syncToExportToImportRequest() throws {
        let cipher = try JSONSerialization.jsonObject(with: CipherEditor.newCipher(
            kind: .login, edit: CipherEdit(name: "GitHub", notes: "n", username: "usagi", password: "pw", totp: "JBSW", uri: "https://github.com"),
            key: key)) as! [String: Any]
        var withMeta = cipher
        withMeta["id"] = "c1"; withMeta["folderId"] = "f1"; withMeta["organizationId"] = NSNull()
        var trashed = withMeta
        trashed["id"] = "c2"; trashed["deletedDate"] = "2026-01-01T00:00:00Z"
        let sync: [String: Any] = [
            "profile": ["id": "u", "email": "usagi@chiikawarden.test", "key": "2.x|y|z", "organizations": []],
            "folders": [["id": "f1", "name": try EncString.encrypt(Data("Work".utf8), with: key).description]],
            "ciphers": [withMeta, trashed],
        ]
        let vault = try VaultExport.plainVault(syncData: JSONSerialization.data(withJSONObject: sync), userKey: key)
        #expect(vault.items.count == 1, "Trash is not exported")
        #expect(vault.folders.first?["name"] as? String == "Work")

        let preview = try VaultImport.preview(VaultExport.json(folders: vault.folders, items: vault.items))
        let body = try VaultImport.requestBody(items: preview.items, folders: preview.folders, key: otherKey)
        let root = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sent = try #require((root["ciphers"] as? [[String: Any]])?.first)
        #expect(!String(decoding: body, as: UTF8.self).contains("usagi"), "nothing leaves unencrypted")
        let back = try #require(CipherFields.decrypt(sent, key: otherKey) as? [String: Any])
        let login = back["login"] as? [String: Any]
        #expect(back["name"] as? String == "GitHub" && back["notes"] as? String == "n")
        #expect(login?["username"] as? String == "usagi" && login?["password"] as? String == "pw" && login?["totp"] as? String == "JBSW")
        #expect((root["folderRelationships"] as? [[String: Int]]) == [["key": 0, "value": 0]])
        let folderName = ((root["folders"] as? [[String: Any]])?.first?["name"] as? String).flatMap { try? EncString($0).decryptString(with: otherKey) }
        #expect(folderName == "Work")
    }
}
