import Compression
import Foundation

// Other password managers' exports, mapped the way Bitwarden's own importers map them.

extension VaultImport {
    /// Builds a login item in Bitwarden's export shape.
    static func loginItem(name: String, uri: String, username: String, password: String, totp: String = "",
                          notes: String = "", favorite: Bool = false, fields: [(String, String, Bool)] = []) -> [String: Any] {
        var login: [String: Any] = ["username": username, "password": password]
        if !totp.isEmpty { login["totp"] = totp }
        let uris = uri.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !uris.isEmpty { login["uris"] = uris.map { ["uri": $0, "match": NSNull()] } }
        var item: [String: Any] = ["type": 1, "name": name.isEmpty ? (host(uri) ?? "--") : name, "login": login,
                                   "favorite": favorite, "reprompt": 0]
        if !notes.isEmpty { item["notes"] = notes }
        if !fields.isEmpty {
            item["fields"] = fields.map { ["name": $0.0, "value": $0.1, "type": $0.2 ? 1 : 0, "linkedId": NSNull()] }
        }
        return item
    }

    static func noteItem(name: String, notes: String, favorite: Bool = false) -> [String: Any] {
        ["type": 2, "name": name.isEmpty ? "--" : name, "notes": notes, "secureNote": ["type": 0], "favorite": favorite, "reprompt": 0]
    }

    /// Folder index for a name, adding it if new ("" = no folder).
    static func folder(_ name: String, in folders: inout [String]) -> Int? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if let i = folders.firstIndex(of: name) { return i }
        folders.append(name)
        return folders.count - 1
    }

    // MARK: CSV formats (detected by header)

    /// Formats beyond Bitwarden's and the browsers': nil if the header isn't one of them.
    static func otherCSV(header: [String], rows: [[String]]) -> ImportPreview? {
        func col(_ name: String) -> Int? { header.firstIndex(of: name) }
        func has(_ names: String...) -> Bool { names.allSatisfy { col($0) != nil } }
        func v(_ row: [String], _ name: String) -> String {
            guard let i = col(name), i < row.count else { return "" }
            return row[i]
        }
        var folders: [String] = []
        var items: [ImportedItem] = []
        let format: ImportPreview.Format

        if has("url", "username", "password", "extra", "name", "grouping") {
            format = .lastPassCSV // url,username,password,totp,extra,name,grouping,fav
            for row in rows {
                let url = v(row, "url")
                let folderIndex = folder(v(row, "grouping"), in: &folders)
                let item = url == "http://sn"
                    ? noteItem(name: v(row, "name"), notes: v(row, "extra"), favorite: v(row, "fav") == "1")
                    : loginItem(name: v(row, "name"), uri: url, username: v(row, "username"), password: v(row, "password"),
                                totp: v(row, "totp"), notes: v(row, "extra"), favorite: v(row, "fav") == "1")
                items.append(ImportedItem(json: item, folder: folderIndex))
            }
        } else if has("group", "title", "username", "password", "url", "notes") {
            format = .keePassXCCSV // "Group","Title","Username","Password","URL","Notes","TOTP",…
            for row in rows {
                // "Root/Work/Servers" → "Work/Servers"
                let path = v(row, "group").split(separator: "/").dropFirst().joined(separator: "/")
                items.append(ImportedItem(json: loginItem(name: v(row, "title"), uri: v(row, "url"), username: v(row, "username"),
                                                          password: v(row, "password"), totp: v(row, "totp"), notes: v(row, "notes")),
                                          folder: folder(path, in: &folders)))
            }
        } else if has("type", "name", "url", "email", "username", "password", "note", "totp", "vault") {
            format = .protonPassCSV // type,name,url,email,username,password,note,totp,createTime,modifyTime,vault
            for row in rows {
                let folderIndex = folder(v(row, "vault"), in: &folders)
                switch v(row, "type").lowercased() {
                case "note":
                    items.append(ImportedItem(json: noteItem(name: v(row, "name"), notes: v(row, "note")), folder: folderIndex))
                default:
                    let username = v(row, "username").isEmpty ? v(row, "email") : v(row, "username")
                    var extra: [(String, String, Bool)] = []
                    if !v(row, "username").isEmpty, !v(row, "email").isEmpty { extra.append(("Email", v(row, "email"), false)) }
                    items.append(ImportedItem(json: loginItem(name: v(row, "name"), uri: v(row, "url"), username: username,
                                                              password: v(row, "password"), totp: v(row, "totp"),
                                                              notes: v(row, "note"), fields: extra), folder: folderIndex))
                }
            }
        } else if has("username", "username2", "title", "password", "note", "url", "category") {
            format = .dashlaneCSV // username,username2,username3,title,password,note,url,category,otpSecret
            for row in rows {
                var extra: [(String, String, Bool)] = []
                for k in ["username2", "username3"] where !v(row, k).isEmpty { extra.append(("Username", v(row, k), false)) }
                items.append(ImportedItem(json: loginItem(name: v(row, "title"), uri: v(row, "url"), username: v(row, "username"),
                                                          password: v(row, "password"), totp: v(row, "otpsecret"),
                                                          notes: v(row, "note"), fields: extra),
                                          folder: folder(v(row, "category"), in: &folders)))
            }
        } else if has("title", "url", "username", "password"), col("archived") != nil || col("tags") != nil {
            format = .onePasswordCSV // Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes
            for row in rows where v(row, "archived").lowercased() != "true" {
                items.append(ImportedItem(json: loginItem(name: v(row, "title"), uri: v(row, "url"), username: v(row, "username"),
                                                          password: v(row, "password"), totp: v(row, "otpauth"), notes: v(row, "notes"),
                                                          favorite: v(row, "favorite").lowercased() == "true")))
            }
        } else {
            return nil
        }
        return ImportPreview(format: format, folders: folders, items: items, problems: [])
    }

    // MARK: KeePass 2 XML

    static func keePassXML(_ data: Data) throws(ImportError) -> ImportPreview {
        let reader = KeePassXMLReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), reader.sawKeePassFile else { throw .unsupported }
        var folders: [String] = []
        var items: [ImportedItem] = []
        for entry in reader.entries {
            var strings = entry.strings
            let title = strings.removeValue(forKey: "Title") ?? ""
            let username = strings.removeValue(forKey: "UserName") ?? ""
            let password = strings.removeValue(forKey: "Password") ?? ""
            let url = strings.removeValue(forKey: "URL") ?? ""
            let notes = strings.removeValue(forKey: "Notes") ?? ""
            let totp = strings.removeValue(forKey: "otp") ?? strings.removeValue(forKey: "TOTP Seed") ?? ""
            strings.removeValue(forKey: "TOTP Settings")
            let fields = strings.sorted { $0.key < $1.key }.map { ($0.key, $0.value, entry.protected.contains($0.key)) }
            let item = username.isEmpty && password.isEmpty && url.isEmpty
                ? noteItem(name: title, notes: notes)
                : loginItem(name: title, uri: url, username: username, password: password, totp: totp, notes: notes, fields: fields)
            items.append(ImportedItem(json: item, folder: folder(entry.groupPath.joined(separator: "/"), in: &folders)))
        }
        guard !items.isEmpty else { throw .empty }
        return ImportPreview(format: .keePassXML, folders: folders, items: items, problems: [])
    }

    // MARK: 1Password .1pux

    static func onePux(_ data: Data) throws(ImportError) -> ImportPreview {
        guard let json = Zip.file(named: "export.data", in: data),
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { throw .unsupported }
        var folders: [String] = []
        var items: [ImportedItem] = []
        var problems: [ImportProblem] = []
        var index = 0
        for account in root["accounts"] as? [[String: Any]] ?? [] {
            for vault in account["vaults"] as? [[String: Any]] ?? [] {
                let vaultName = (vault["attrs"] as? [String: Any])?["name"] as? String ?? ""
                for raw in vault["items"] as? [[String: Any]] ?? [] {
                    index += 1
                    if (raw["state"] as? String) == "archived" { continue }
                    let overview = raw["overview"] as? [String: Any] ?? [:]
                    let details = raw["details"] as? [String: Any] ?? [:]
                    let title = overview["title"] as? String ?? ""
                    let notes = details["notesPlain"] as? String ?? ""
                    let favorite = (raw["favIndex"] as? Int ?? 0) > 0
                    var username = "", password = "", totp = ""
                    for field in details["loginFields"] as? [[String: Any]] ?? [] {
                        switch field["designation"] as? String {
                        case "username": username = field["value"] as? String ?? ""
                        case "password": password = field["value"] as? String ?? ""
                        default: break
                        }
                    }
                    var extra: [(String, String, Bool)] = []
                    for section in details["sections"] as? [[String: Any]] ?? [] {
                        for field in section["fields"] as? [[String: Any]] ?? [] {
                            let value = field["value"] as? [String: Any] ?? [:]
                            let name = field["title"] as? String ?? ""
                            if let otp = value["totp"] as? String, totp.isEmpty { totp = otp; continue }
                            if let s = (value["string"] ?? value["concealed"] ?? value["email"] ?? value["url"] ?? value["phone"]) as? String, !s.isEmpty {
                                extra.append((name, s, value["concealed"] != nil))
                            }
                        }
                    }
                    if password.isEmpty, let p = details["password"] as? String { password = p } // Password items
                    let urls = (overview["urls"] as? [[String: Any]])?.compactMap { $0["url"] as? String } ?? []
                    let url = urls.isEmpty ? (overview["url"] as? String ?? "") : urls.joined(separator: ",")
                    let category = raw["categoryUuid"] as? String ?? ""
                    let item: [String: Any]
                    switch category {
                    case "001", "005": // Login, Password
                        item = loginItem(name: title, uri: url, username: username, password: password, totp: totp,
                                         notes: notes, favorite: favorite, fields: extra)
                    case "003": // Secure Note
                        item = noteItem(name: title, notes: notes, favorite: favorite)
                    default:
                        // Other kinds keep their fields as text in a secure note, as Bitwarden's importer does for unknowns.
                        let text = ([notes] + extra.map { "\($0.0): \($0.1)" }).filter { !$0.isEmpty }.joined(separator: "\n")
                        item = noteItem(name: title, notes: text, favorite: favorite)
                        if extra.isEmpty && notes.isEmpty { problems.append(.unknownType(item: index)); continue }
                    }
                    items.append(ImportedItem(json: item, folder: folder(vaultName, in: &folders)))
                }
            }
        }
        guard !items.isEmpty else { throw problems.isEmpty ? .empty : .unsupported }
        // One vault (the usual "Personal") needs no folder.
        if folders.count == 1 { items = items.map { var i = $0; i.folder = nil; return i }; folders = [] }
        return ImportPreview(format: .onePassword1pux, folders: folders, items: items, problems: problems)
    }
}

/// Collects KeePass 2 XML entries with their group path. Entries under History are older versions: skipped.
private final class KeePassXMLReader: NSObject, XMLParserDelegate {
    struct Entry { var groupPath: [String]; var strings: [String: String] = [:]; var protected: Set<String> = [] }
    var entries: [Entry] = []
    var sawKeePassFile = false

    private var groups: [String] = []
    private var current: Entry?
    private var historyDepth = 0
    private var key: String?
    private var value: String?
    private var text = ""
    private var valueProtected = false
    private var awaitingGroupName = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "KeePassFile": sawKeePassFile = true
        case "Group": groups.append(""); awaitingGroupName = true
        case "History": historyDepth += 1
        case "Entry" where historyDepth == 0: current = Entry(groupPath: Array(groups.dropFirst()).filter { !$0.isEmpty })
        case "String": key = nil; value = nil
        case "Value": valueProtected = attributes["Protected"] == "True"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "Name" where awaitingGroupName && current == nil:
            groups[groups.count - 1] = text; awaitingGroupName = false
        case "Group": groups.removeLast()
        case "History": historyDepth -= 1
        case "Key": key = text
        case "Value": value = text
        case "String":
            if historyDepth == 0, let key, let value, current != nil {
                if !value.isEmpty { current?.strings[key] = value }
                if valueProtected { current?.protected.insert(key) }
            }
        case "Entry" where historyDepth == 0:
            if let current { entries.append(current) }
            current = nil
        default: break
        }
    }
}

/// Just enough ZIP to read one file: the central directory, stored or deflated entries.
enum Zip {
    static func file(named wanted: String, in data: Data) -> Data? {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 1 < bytes.count ? Int(bytes[o]) | Int(bytes[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        // End of central directory: signature 0x06054b50, searched from the end.
        guard bytes.count > 22, let eocd = stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1)
            .first(where: { u32($0) == 0x0605_4B50 }) else { return nil }
        var offset = u32(eocd + 16)
        for _ in 0..<u16(eocd + 10) {
            guard u32(offset) == 0x0201_4B50 else { return nil }
            let method = u16(offset + 10), compressed = u32(offset + 20), size = u32(offset + 24)
            let nameLength = u16(offset + 28), extraLength = u16(offset + 30), commentLength = u16(offset + 32)
            let local = u32(offset + 42)
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength
            guard name == wanted, u32(local) == 0x0403_4B50 else { continue }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + compressed <= bytes.count else { return nil }
            let payload = Array(bytes[start..<(start + compressed)])
            switch method {
            case 0: return Data(payload)
            case 8:
                var out = [UInt8](repeating: 0, count: max(size, 1))
                let n = compression_decode_buffer(&out, out.count, payload, payload.count, nil, COMPRESSION_ZLIB)
                return n == size ? Data(out.prefix(n)) : nil
            default: return nil
            }
        }
        return nil
    }
}
