import Foundation
import Testing
@testable import VaultwardenAPI

@Suite struct ImportFormatsTests {
    func login(_ item: ImportedItem) -> [String: Any] { item.json["login"] as? [String: Any] ?? [:] }

    @Test func lastPass() throws {
        let csv = """
        url,username,password,totp,extra,name,grouping,fav
        https://github.com/login,usagi,pw1,JBSW,a note,GitHub,Work,1
        http://sn,,,,"secret, text",Wi-Fi,,0
        """
        let p = try VaultImport.preview(Data(csv.utf8))
        #expect(p.format == .lastPassCSV)
        #expect(p.folders == ["Work"])
        #expect(p.items[0].name == "GitHub" && p.items[0].folder == 0 && p.items[0].json["favorite"] as? Bool == true)
        #expect(login(p.items[0])["totp"] as? String == "JBSW" && p.items[0].json["notes"] as? String == "a note")
        #expect(p.items[1].type == 2 && p.items[1].json["notes"] as? String == "secret, text")
    }

    @Test func keePassXCCSV() throws {
        let csv = """
        "Group","Title","Username","Password","URL","Notes","TOTP","Icon","Last Modified","Created"
        "Root/Work/Servers","NAS","admin","pw","https://nas.home.arpa","","otpauth://totp/x?secret=ABC","0","",""
        """
        let p = try VaultImport.preview(Data(csv.utf8))
        #expect(p.format == .keePassXCCSV)
        #expect(p.folders == ["Work/Servers"] && p.items[0].folder == 0)
        #expect(login(p.items[0])["totp"] as? String == "otpauth://totp/x?secret=ABC")
    }

    @Test func protonPassAndDashlane() throws {
        let proton = """
        type,name,url,email,username,password,note,totp,createTime,modifyTime,vault
        login,GitHub,https://github.com,u@x.com,,pw,,,1,2,Personal
        note,Recovery,,,,,codes here,,1,2,Personal
        """
        let p = try VaultImport.preview(Data(proton.utf8))
        #expect(p.format == .protonPassCSV && p.items.count == 2)
        #expect(p.items[0].username == "u@x.com" && p.items[1].type == 2)
        let dashlane = """
        username,username2,username3,title,password,note,url,category,otpSecret
        usagi,alt,,GitHub,pw,,https://github.com,Dev,JBSW
        """
        let d = try VaultImport.preview(Data(dashlane.utf8))
        #expect(d.format == .dashlaneCSV && d.folders == ["Dev"])
        #expect((d.items[0].json["fields"] as? [[String: Any]])?.first?["value"] as? String == "alt")
    }

    @Test func onePasswordCSVSkipsArchived() throws {
        let csv = """
        Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes
        GitHub,https://github.com,usagi,pw,,true,false,,n
        Old,https://old.example,u,p,,false,true,,
        """
        let p = try VaultImport.preview(Data(csv.utf8))
        #expect(p.format == .onePasswordCSV && p.items.map(\.name) == ["GitHub"])
        #expect(p.items[0].json["favorite"] as? Bool == true)
    }

    @Test func keePassXMLSkipsHistory() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8" standalone="yes"?>
        <KeePassFile><Root><Group><Name>Database</Name>
          <Group><Name>Work</Name>
            <Entry>
              <String><Key>Title</Key><Value>GitHub</Value></String>
              <String><Key>UserName</Key><Value>usagi</Value></String>
              <String><Key>Password</Key><Value Protected="True">pw-now</Value></String>
              <String><Key>URL</Key><Value>https://github.com</Value></String>
              <String><Key>PIN</Key><Value Protected="True">0420</Value></String>
              <History><Entry><String><Key>Password</Key><Value>pw-old</Value></String></Entry></History>
            </Entry>
          </Group>
          <Entry><String><Key>Title</Key><Value>Note only</Value></String><String><Key>Notes</Key><Value>hello</Value></String></Entry>
        </Group></Root></KeePassFile>
        """
        let p = try VaultImport.preview(Data(xml.utf8))
        #expect(p.format == .keePassXML && p.items.count == 2)
        #expect(p.folders == ["Work"] && p.items[0].folder == 0 && p.items[1].folder == nil)
        #expect(login(p.items[0])["password"] as? String == "pw-now", "History versions are not imported")
        let pin = (p.items[0].json["fields"] as? [[String: Any]])?.first
        #expect(pin?["name"] as? String == "PIN" && pin?["type"] as? Int == 1)
        #expect(p.items[1].type == 2 && p.items[1].json["notes"] as? String == "hello")
    }

    /// A real deflated .1pux, made with the system's zip tool.
    @Test func onePassword1pux() throws {
        let export: [String: Any] = ["accounts": [["vaults": [
            ["attrs": ["name": "Personal"], "items": [
                ["categoryUuid": "001", "favIndex": 1,
                 "overview": ["title": "GitHub", "urls": [["url": "https://github.com"]]],
                 "details": ["loginFields": [["designation": "username", "value": "usagi"], ["designation": "password", "value": "pw"]],
                             "notesPlain": "n",
                             "sections": [["fields": [["title": "one-time password", "value": ["totp": "otpauth://totp/x?secret=ABC"]],
                                                      ["title": "PIN", "value": ["concealed": "0420"]]]]]]],
                ["categoryUuid": "003", "overview": ["title": "Wi-Fi"], "details": ["notesPlain": "pochi-net"]],
                ["categoryUuid": "001", "state": "archived", "overview": ["title": "Old"], "details": [:]],
            ]],
        ]]]]
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try JSONSerialization.data(withJSONObject: export).write(to: dir.appending(path: "export.data"))
        try Data(repeating: 0x41, count: 4096).write(to: dir.appending(path: "export.attributes"))
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = dir
        zip.arguments = ["-q", "-9", "export.1pux", "export.attributes", "export.data"]
        try zip.run(); zip.waitUntilExit()

        let p = try VaultImport.preview(Data(contentsOf: dir.appending(path: "export.1pux")))
        #expect(p.format == .onePassword1pux)
        #expect(p.items.map(\.name) == ["GitHub", "Wi-Fi"], "archived items are skipped")
        #expect(p.folders.isEmpty, "a single vault needs no folder")
        #expect(login(p.items[0])["totp"] as? String == "otpauth://totp/x?secret=ABC" && login(p.items[0])["password"] as? String == "pw")
        #expect((p.items[0].json["fields"] as? [[String: Any]])?.first?["type"] as? Int == 1)
        #expect(p.items[1].type == 2 && p.items[1].json["notes"] as? String == "pochi-net")
    }

    @Test func browsersStillDetected() throws {
        // LastPass and 1Password share columns with Chrome and Safari; plain browser files must still read as browsers.
        #expect(try VaultImport.preview(Data("name,url,username,password,note\na,https://a.com,u,p,\n".utf8)).format == .chromeCSV)
        #expect(try VaultImport.preview(Data("Title,URL,Username,Password,Notes,OTPAuth\na,https://a.com,u,p,,\n".utf8)).format == .safariCSV)
    }
}
