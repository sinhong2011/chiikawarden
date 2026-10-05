import ChiikawaCrypto
import Foundation

// Shared by the app and the AutoFill extension.

struct VaultItem: Identifiable, Hashable {
    enum Kind: Int { case login = 1, note = 2, card = 3, identity = 4, sshKey = 5 }

    let id: String
    /// Which saved account this item belongs to (several can be unlocked at once).
    var accountId = ""
    var kind: Kind = .login
    let name: String
    var username: String?
    let host: String?
    let password: String?
    let totp: TOTP?
    let notes: String?
    var totpSecret: String?
    var uri: String?
    let favorite: Bool
    var hasPasskey = false
    var folderId: String?
    var isDeleted = false
    var organizationId: String?
    var collectionIds: [String] = []
    /// Filled in after sync: how many other items share this password.
    var reuseCount = 0

    var hasTOTP: Bool { totp != nil }

    /// Extra fields for non-login kinds (card, identity, SSH key), in display order.
    var fields: [ItemField] = []

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// A folder, organization or collection shown in the sidebar.
struct Grouping: Identifiable, Hashable {
    let id: String
    let name: String
    var children: [Grouping] = []
}

struct ItemField: Hashable, Identifiable {
    var id: String { label }
    let label: String
    let value: String
    var secret = false
    var monospaced = false
}

extension TOTP: @retroactive Hashable {
    public func hash(into h: inout Hasher) { h.combine(secret) }

    /// "621 115" — grouped for reading aloud and typing.
    func displayCode(at date: Date = .now) -> String {
        let c = code(at: date)
        return c.prefix(c.count / 2) + " " + c.suffix(c.count - c.count / 2)
    }
}


extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
