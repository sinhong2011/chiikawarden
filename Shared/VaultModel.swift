import ChiikawaCrypto
import Foundation
import VaultwardenAPI

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
    var favorite: Bool
    var hasPasskey = false
    var folderId: String?
    /// Decrypted folder name, e.g. "Work/Servers" (nested by "/").
    var folderName: String?
    var isDeleted = false
    var organizationId: String?
    var collectionIds: [String] = []
    /// Filled in after sync: how many other items share this password.
    var reuseCount = 0

    var hasTOTP: Bool { totp != nil }

    /// Extra fields for non-login kinds (card, identity, SSH key), in display order.
    var fields: [ItemField] = []
    /// Raw card / identity / SSH-key properties by API name, for editing.
    var properties: [String: String] = [:]
    /// Custom fields (text, hidden, boolean, linked).
    var customFields: [CustomField] = []
    /// Decrypted passkeys (ES256) on this login.
    var passkeys: [PasskeyCredential] = []
    var attachments: [Attachment] = []

    /// File metadata; contents are fetched and decrypted on demand.
    struct Attachment: Identifiable, Hashable, Sendable {
        var id: String
        var fileName: String
        var size: Int
        var sizeName: String
        var url: String?
        /// Decrypts the file contents.
        var fileKey: SymmetricKeyPair
        static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.fileName == b.fileName && a.size == b.size }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

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

/// A decrypted Send owned by one of the accounts.
struct SendItem: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case text, file }
    var id: String
    var accountId: String
    var accessId: String
    var kind: Kind
    var name: String
    var notes: String?
    var text: String?
    var hideText: Bool
    var fileName: String?
    var sizeName: String?
    /// Goes in the link's fragment; derives the Send key.
    var keyMaterial: Data
    var accessCount: Int
    var maxAccessCount: Int?
    var hasPassword: Bool
    var disabled: Bool
    var deletionDate: Date?
    var expirationDate: Date?

    var isExpired: Bool { expirationDate.map { $0 < .now } ?? false }
    var isUsedUp: Bool { maxAccessCount.map { accessCount >= $0 } ?? false }
}
