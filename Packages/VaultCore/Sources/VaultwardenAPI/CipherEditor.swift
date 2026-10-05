import ChiikawaCrypto
import Foundation

/// What the user can change on an item. `nil` means "leave as is"; an empty string clears the field.
public struct CipherEdit: Sendable, Equatable {
    public var name: String?
    public var notes: String?
    public var username: String?
    public var password: String?
    public var totp: String?
    public var uri: String?
    public var favorite: Bool?
    /// `.some(nil)` moves the item out of any folder.
    public var folderId: String??

    public init(name: String? = nil, notes: String? = nil, username: String? = nil, password: String? = nil,
                totp: String? = nil, uri: String? = nil, favorite: Bool? = nil, folderId: String?? = nil) {
        self.name = name; self.notes = notes; self.username = username; self.password = password
        self.totp = totp; self.uri = uri; self.favorite = favorite; self.folderId = folderId
    }
}

/// Edits ciphers by patching the server's own JSON, so fields we don't model — the per-item `key`,
/// passkeys (`fido2Credentials`), custom fields, attachments — survive an edit untouched.
public enum CipherEditor {
    public enum Kind: Int, Sendable { case login = 1, secureNote = 2 }

    /// A brand-new personal item.
    public static func newCipher(kind: Kind, edit: CipherEdit, key: SymmetricKeyPair) throws -> Data {
        var dict: [String: Any] = ["type": kind.rawValue, "favorite": false, "reprompt": 0]
        if kind == .login { dict["login"] = [String: Any]() }
        if kind == .secureNote { dict["secureNote"] = ["type": 0] }
        try apply(edit, to: &dict, key: key, now: .now)
        return try JSONSerialization.data(withJSONObject: dict)
    }

    /// Patches one cipher from a sync payload. Returns the PUT body.
    public static func updatedCipher(raw: Data, edit: CipherEdit, key: SymmetricKeyPair, now: Date = .now) throws -> Data {
        guard var dict = normalize(try JSONSerialization.jsonObject(with: raw)) as? [String: Any] else {
            throw APIError.http(status: -1, message: "Malformed cipher")
        }
        // Optimistic concurrency: the server rejects the edit if someone changed it meanwhile.
        if let revision = dict["revisionDate"] { dict["lastKnownRevisionDate"] = revision }
        try apply(edit, to: &dict, key: key, now: now)
        return try JSONSerialization.data(withJSONObject: dict)
    }

    /// Extracts each cipher's raw JSON from a sync payload, keyed by id.
    public static func rawCiphers(fromSync data: Data) -> [String: Data] {
        guard let root = normalize(try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ciphers = root["ciphers"] as? [[String: Any]] else { return [:] }
        var out: [String: Data] = [:]
        for c in ciphers {
            if let id = c["id"] as? String, let d = try? JSONSerialization.data(withJSONObject: c) { out[id] = d }
        }
        return out
    }

    private static func apply(_ edit: CipherEdit, to dict: inout [String: Any], key: SymmetricKeyPair, now: Date) throws {
        func enc(_ s: String) throws -> Any { s.isEmpty ? NSNull() : try EncString.encrypt(Data(s.utf8), with: key).description }
        func dec(_ any: Any?) -> String? { (any as? String).flatMap { try? EncString($0).decryptString(with: key) } }

        if let name = edit.name { dict["name"] = try enc(name) }
        if let notes = edit.notes { dict["notes"] = try enc(notes) }
        if let favorite = edit.favorite { dict["favorite"] = favorite }
        if let folder = edit.folderId { dict["folderId"] = folder ?? NSNull() }

        guard (dict["type"] as? Int) == Kind.login.rawValue else { return }
        var login = dict["login"] as? [String: Any] ?? [:]
        if let username = edit.username { login["username"] = try enc(username) }
        if let totp = edit.totp { login["totp"] = try enc(totp) }
        if let password = edit.password {
            let old = dec(login["password"])
            if let old, old != password {
                // Keep what was there: the previous password goes to history (newest first, capped at 5).
                var history = dict["passwordHistory"] as? [[String: Any]] ?? []
                history.insert(["password": try enc(old), "lastUsedDate": ISO8601DateFormatter().string(from: now)], at: 0)
                dict["passwordHistory"] = Array(history.prefix(5))
                login["passwordRevisionDate"] = ISO8601DateFormatter().string(from: now)
            }
            login["password"] = try enc(password)
        }
        if let uri = edit.uri {
            var uris = login["uris"] as? [[String: Any]] ?? []
            if uri.isEmpty {
                if !uris.isEmpty { uris.removeFirst() }
            } else if uris.isEmpty {
                uris = [["uri": try enc(uri), "match": NSNull()]]
            } else {
                uris[0]["uri"] = try enc(uri)
                uris[0].removeValue(forKey: "uriChecksum") // stale after the change
            }
            login["uris"] = uris
        }
        dict["login"] = login
    }

    /// Older Vaultwarden returns PascalCase; send camelCase everywhere (all servers accept it).
    static func normalize(_ any: Any?) -> Any? {
        switch any {
        case let d as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in d {
                let key = k.first.map { $0.lowercased() + k.dropFirst() } ?? k
                out[key] = normalize(v) ?? NSNull()
            }
            return out
        case let a as [Any]:
            return a.map { normalize($0) ?? NSNull() }
        default:
            return any
        }
    }
}
