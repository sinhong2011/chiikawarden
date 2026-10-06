import AppIntents
import AppKit
import TriCrypto

// Shortcuts / Spotlight actions. Entities expose only names and usernames; secrets are copied or
// returned only by an explicit action while the vault is unlocked.

extension PasswordGenerator {
    /// The options last used in the generator popover.
    static var saved: PasswordGenerator {
        UserDefaults.standard.data(forKey: "generator").flatMap { try? JSONDecoder().decode(PasswordGenerator.self, from: $0) }
            ?? PasswordGenerator()
    }
}

enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case locked, noPassword, noCode, notFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .locked: "Triwarden is locked. Unlock it first."
        case .noPassword: "That item has no password."
        case .noCode: "That item has no one-time code."
        case .notFound: "That item is no longer in your vault."
        }
    }
}

struct VaultItemEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Vault Item"
    static let defaultQuery = VaultItemQuery()

    let id: String
    let name: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }

    init(_ item: VaultItem) {
        id = item.id
        name = item.name
        subtitle = item.username ?? item.host ?? ""
    }
}

struct VaultItemQuery: EntityStringQuery {
    @MainActor private var model: AppModel {
        get throws {
            guard let model = AppModel.current, model.isUnlocked else { throw IntentFailure.locked }
            return model
        }
    }

    @MainActor func entities(for identifiers: [String]) async throws -> [VaultItemEntity] {
        try model.items.filter { identifiers.contains($0.id) }.map(VaultItemEntity.init)
    }

    @MainActor func entities(matching string: String) async throws -> [VaultItemEntity] {
        try model.items.filter {
            !$0.isDeleted && !$0.isArchived && ($0.name.localizedCaseInsensitiveContains(string)
                || ($0.username?.localizedCaseInsensitiveContains(string) ?? false)
                || ($0.host?.localizedCaseInsensitiveContains(string) ?? false))
        }
        .prefix(30).map(VaultItemEntity.init)
    }

    @MainActor func suggestedEntities() async throws -> [VaultItemEntity] {
        let items = try model.items.filter { !$0.isDeleted && !$0.isArchived && $0.kind == .login }
        return (items.filter(\.favorite) + items.filter { !$0.favorite }).prefix(20).map(VaultItemEntity.init)
    }
}

@MainActor
private func unlockedItem(_ entity: VaultItemEntity) throws -> (AppModel, VaultItem) {
    guard let model = AppModel.current, model.isUnlocked else { throw IntentFailure.locked }
    guard let item = model.items.first(where: { $0.id == entity.id }) else { throw IntentFailure.notFound }
    return (model, item)
}

struct CopyPasswordIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Password"
    static let description = IntentDescription("Copies an item's password. It's cleared from the clipboard after the delay set in Triwarden.")

    @Parameter(title: "Item") var item: VaultItemEntity

    static var parameterSummary: some ParameterSummary { Summary("Copy the password of \(\.$item)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let (model, vaultItem) = try unlockedItem(item)
        guard let password = vaultItem.password else { throw IntentFailure.noPassword }
        model.copy(password, label: String(localized: "Password"))
        return .result(dialog: "Copied the password for \(vaultItem.name).")
    }
}

struct GetOneTimeCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get One-Time Code"
    static let description = IntentDescription("Returns an item's current one-time code and copies it.")

    @Parameter(title: "Item") var item: VaultItemEntity

    static var parameterSummary: some ParameterSummary { Summary("Get the one-time code for \(\.$item)") }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let (model, vaultItem) = try unlockedItem(item)
        guard let totp = vaultItem.totp else { throw IntentFailure.noCode }
        let code = totp.code()
        model.copy(code, label: String(localized: "Code"))
        return .result(value: code, dialog: "\(code)")
    }
}

struct GeneratePasswordIntent: AppIntent {
    static let title: LocalizedStringResource = "Generate Password"
    static let description = IntentDescription("Creates a random password with your generator settings. Works while locked.")

    @Parameter(title: "Length", default: 20, inclusiveRange: (8, 128)) var length: Int

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var generator = PasswordGenerator.saved
        generator.length = length
        return .result(value: generator.generate())
    }
}

struct LockVaultIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Vault"
    static let description = IntentDescription("Locks every account in Triwarden.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppModel.current?.lock()
        return .result(dialog: "Triwarden is locked.")
    }
}

struct TriwardenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CopyPasswordIntent(), phrases: ["Copy a password with \(.applicationName)",
                                                            "Copy \(\.$item) password with \(.applicationName)"],
                    shortTitle: "Copy Password", systemImageName: "key")
        AppShortcut(intent: GetOneTimeCodeIntent(), phrases: ["Get a code with \(.applicationName)",
                                                              "Get \(\.$item) code with \(.applicationName)"],
                    shortTitle: "One-Time Code", systemImageName: "clock.badge.checkmark")
        AppShortcut(intent: GeneratePasswordIntent(), phrases: ["Generate a password with \(.applicationName)"],
                    shortTitle: "Generate Password", systemImageName: "dice")
        AppShortcut(intent: LockVaultIntent(), phrases: ["Lock \(.applicationName)"],
                    shortTitle: "Lock Vault", systemImageName: "lock")
    }
}

/// Services menu: "Generate Password" inserts a fresh password into the focused text field of any app.
final class ServicesProvider: NSObject {
    @objc func generatePassword(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        pasteboard.clearContents()
        pasteboard.setString(PasswordGenerator.saved.generate(), forType: .string)
    }
}
