import ChiikawaCrypto
import Foundation
import Observation
import VaultwardenAPI

/// One unlocked account: its key, decrypted vault, server connection and live sync.
@MainActor @Observable
final class AccountSession {
    let account: SavedAccount
    private(set) var items: [VaultItem] = []
    private(set) var folders: [Grouping] = []
    private(set) var organizations: [Grouping] = []
    private(set) var sends: [SendItem] = []
    private(set) var hiddenCount = 0
    /// Sites that share sign-ins, from the server's domain rules.
    private(set) var equivalents = EquivalentDomains.none
    private(set) var lastSynced: Date?
    private(set) var isSyncing = false

    private let userKey: SymmetricKeyPair
    private(set) var client: VaultClient?
    private var rawCiphers: [String: Data] = [:]
    private var keyring: Keyring?
    private var live: LiveSync?
    private var debounce: Task<Void, Never>?
    private var periodic: Timer?
    private let makeClient: (ServerEnvironment) -> VaultClient
    private let makeSession: () -> URLSession
    /// Called whenever items change, so the app can merge and republish.
    var onChange: () -> Void = {}

    var id: String { account.id }

    init(account: SavedAccount, userKey: SymmetricKeyPair, client: VaultClient? = nil,
         makeClient: @escaping (ServerEnvironment) -> VaultClient, makeSession: @escaping () -> URLSession) {
        self.account = account
        self.userKey = userKey
        self.client = client
        self.makeClient = makeClient
        self.makeSession = makeSession
        if let cache = AccountStore.loadCache(account.id) { try? load(cache) }
    }

    var environment: ServerEnvironment? { account.environment }

    // MARK: Sync

    /// Pulls the vault, caches the (still encrypted) payload, rebuilds, then listens for live changes.
    func refresh() async throws {
        guard let client else { return }
        isSyncing = true
        defer { isSyncing = false }
        let data = try await client.syncData()
        AccountStore.saveCache(data, account.id)
        try load(data)
        lastSynced = .now
        await startLiveSync()
    }

    /// Reconnects with the stored refresh token, then syncs. Failures keep the cached vault.
    func resume() async {
        guard let environment, let token = AccountStore.refreshToken(account.id) else { return }
        let client = self.client ?? makeClient(environment)
        self.client = client
        do {
            await client.restore(refreshToken: token)
            AccountStore.setRefreshToken(try await client.refreshAccessToken(), account.id)
            try await refresh()
        } catch {
            // Offline or session expired: keep the cache.
        }
    }

    func scheduleSync() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            do { try await refresh() } catch {
                // The AutoFill extension may have rotated the refresh token meanwhile; use the stored one.
                if let stored = AccountStore.refreshToken(account.id) { await client?.restore(refreshToken: stored) }
                if let token = try? await client?.refreshAccessToken() { AccountStore.setRefreshToken(token, account.id) }
                try? await refresh()
            }
        }
    }

    private func load(_ data: Data) throws {
        let vault = try VaultDecoder.decode(data, userKey: userKey, accountId: account.id)
        items = vault.items
        folders = vault.folders
        organizations = vault.organizations
        sends = vault.sends
        hiddenCount = vault.hiddenCount
        keyring = vault.keyring
        rawCiphers = vault.rawCiphers
        equivalents = EquivalentDomains(syncData: data)
        onChange()
    }

    private func startLiveSync() async {
        guard live == nil, let client, let token = await client.currentAccessToken else { return }
        let live = LiveSync(environment: client.environment, accessToken: token, session: makeSession()) { [weak self] in
            Task { @MainActor in self?.scheduleSync() }
        }
        self.live = live
        do { try await live.start() } catch { self.live = nil }
        if periodic == nil {
            periodic = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleSync() }
            }
        }
    }

    /// Stops background work; the session object is then discarded.
    func close() {
        debounce?.cancel()
        periodic?.invalidate()
        let live = self.live
        self.live = nil
        Task { await live?.stop() }
    }

    // MARK: Touch ID

    func setTouchID(_ enabled: Bool) throws {
        if enabled { try AccountStore.enableTouchID(userKey: userKey, account.id) } else { AccountStore.disableTouchID(account.id) }
    }

    // MARK: Editing

    enum WriteError: Error { case offline }

    func create(_ kind: CipherEditor.Kind, edit: CipherEdit) async throws -> String {
        guard let client else { throw WriteError.offline }
        let id = try await client.createCipher(CipherEditor.newCipher(kind: kind, edit: edit, key: userKey))
        try await refresh()
        return id
    }

    func update(_ id: String, edit: CipherEdit) async throws {
        guard let client, let raw = rawCiphers[id], let key = itemKey(id) else { throw WriteError.offline }
        try await client.updateCipher(id: id, CipherEditor.updatedCipher(raw: raw, edit: edit, key: key))
        try await refresh()
    }

    /// The key that encrypts this item's fields (its own key, the org key, or the user key).
    private func itemKey(_ id: String) -> SymmetricKeyPair? {
        guard let cipher = try? SyncResponse.decode(AccountStore.loadCache(account.id) ?? Data()).ciphers.first(where: { $0.id == id })
        else { return nil }
        return keyring?.key(for: cipher)
    }

    // MARK: Import and export

    /// Vaults this account may import into and export: Personal (nil id), then each organization where the user is an
    /// owner or admin, or has the import/export permission.
    func transferVaults() -> [(id: String?, name: String)] {
        let orgs = (try? SyncResponse.decode(AccountStore.loadCache(account.id) ?? Data()).profile.organizations) ?? nil
        let allowed = Set((orgs ?? []).filter(\.canImportExport).map(\.id))
        return [(nil, String(localized: "Personal"))] + organizations.filter { allowed.contains($0.id) }.map { ($0.id, $0.name) }
    }

    /// The personal vault, or an organization's, as a file in one of Bitwarden's export formats.
    /// Uses the synced (still encrypted) payload, so the export matches the server exactly.
    func export(_ format: VaultExport.Format, filePassword: String? = nil, organizationId: String? = nil) throws -> (data: Data, skipped: Int, count: Int) {
        guard let cache = AccountStore.loadCache(account.id) else { throw WriteError.offline }
        if let organizationId {
            let vault = try VaultExport.organizationVault(syncData: cache, userKey: userKey, organizationId: organizationId)
            let json = { try VaultExport.json(collections: vault.collections, items: vault.items) }
            switch format {
            case .json: return (try json(), 0, vault.items.count)
            case .encryptedJSON: return (try VaultExport.passwordProtected(json(), password: filePassword ?? ""), 0, vault.items.count)
            case .csv:
                let csv = VaultExport.csv(collections: vault.collections, items: vault.items)
                return (csv.data, csv.skipped, vault.items.count - csv.skipped)
            }
        }
        let vault = try VaultExport.plainVault(syncData: cache, userKey: userKey)
        let json = { try VaultExport.json(folders: vault.folders, items: vault.items) }
        switch format {
        case .json: return (try json(), 0, vault.items.count)
        case .encryptedJSON: return (try VaultExport.passwordProtected(json(), password: filePassword ?? ""), 0, vault.items.count)
        case .csv:
            let csv = VaultExport.csv(folders: vault.folders, items: vault.items)
            return (csv.data, csv.skipped, vault.items.count - csv.skipped)
        }
    }

    /// Reads an import file; account-encrypted Bitwarden exports from this account decrypt with its key.
    func previewImport(_ data: Data, password: String?) throws(ImportError) -> ImportPreview {
        try VaultImport.preview(data, password: password, accountKey: userKey)
    }

    /// Encrypts the chosen items here (with the organization's key when importing into one), sends them in one batch,
    /// then syncs. Into an organization, the file's folders become collections.
    func importItems(_ items: [ImportedItem], folders: [String], organizationId: String? = nil) async throws {
        guard let client else { throw WriteError.offline }
        // Bitwarden's cloud caps one import at about 7,000 items: send batches, keeping each folder in one batch.
        for batch in VaultImport.batches(items, limit: 5_000) {
            if let organizationId {
                guard let key = keyring?.orgKeys[organizationId] else { throw WriteError.offline }
                try await client.importOrganizationCiphers(
                    VaultImport.organizationRequestBody(items: batch, collections: folders, organizationId: organizationId, key: key),
                    organizationId: organizationId)
            } else {
                try await client.importCiphers(VaultImport.requestBody(items: batch, folders: folders, key: userKey))
            }
        }
        try await refresh()
    }

    // MARK: Send

    /// Creates a Send and returns its share link.
    func createSend(_ draft: SendDraft) async throws -> URL? {
        guard let client else { throw WriteError.offline }
        let sealed = try draft.seal(userKey: userKey)
        let created = try await client.createSend(sealed)
        try await refresh()
        return created.accessId.flatMap { environment?.sendLink(accessId: $0, keyMaterial: sealed.keyMaterial) }
    }

    func deleteSend(_ id: String) async throws {
        guard let client else { throw WriteError.offline }
        try await client.deleteSend(id: id)
        try await refresh()
    }

    // MARK: Attachments

    func attachmentContents(_ itemId: String, _ attachment: VaultItem.Attachment) async throws -> Data {
        guard let client else { throw WriteError.offline }
        let encrypted = try await client.downloadAttachment(cipherId: itemId, attachmentId: attachment.id, syncedURL: attachment.url)
        return try EncArrayBuffer.decrypt(encrypted, with: attachment.fileKey)
    }

    func addAttachment(_ itemId: String, name: String, contents: Data) async throws {
        guard let client, let key = itemKey(itemId) else { throw WriteError.offline }
        let sealed = try SealedAttachment(name: name, contents: contents, itemKey: key)
        try await client.uploadAttachment(cipherId: itemId, fileName: sealed.fileName, key: sealed.key, encrypted: sealed.encrypted)
        try await refresh()
    }

    func deleteAttachment(_ itemId: String, _ attachmentId: String) async throws {
        guard let client else { throw WriteError.offline }
        try await client.deleteAttachment(cipherId: itemId, attachmentId: attachmentId)
        try await refresh()
    }

    func createFolder(name: String) async throws -> String {
        guard let client else { throw WriteError.offline }
        let id = try await client.createFolder(encryptedName: EncString.encrypt(Data(name.utf8), with: userKey).description)
        try await refresh()
        return id
    }

    func deleteFolder(_ id: String) async throws {
        guard let client else { throw WriteError.offline }
        try await client.deleteFolder(id: id)
        try await refresh()
    }

    func trash(_ id: String) async throws {
        guard let client else { throw WriteError.offline }
        try await client.trashCipher(id: id)
        try await refresh()
    }

    func archive(_ id: String) async throws {
        guard let client else { throw WriteError.offline }
        try await client.archiveCipher(id: id)
        try await refresh()
    }

    func unarchive(_ id: String) async throws {
        guard let client else { throw WriteError.offline }
        try await client.unarchiveCipher(id: id)
        try await refresh()
    }

    func restore(_ id: String) async throws {
        guard let client else { throw WriteError.offline }
        try await client.restoreCipher(id: id)
        try await refresh()
    }

    func deleteForever(_ id: String) async throws {
        guard let client else { throw WriteError.offline }
        try await client.deleteCipher(id: id)
        try await refresh()
    }

    // MARK: Organizations and bulk edits

    /// Moves a personal item into an organization and its collections.
    func share(_ id: String, organizationId: String, collectionIds: [String]) async throws {
        guard let client, let raw = rawCiphers[id], let key = itemKey(id), let orgKey = keyring?.orgKeys[organizationId] else {
            throw WriteError.offline
        }
        let cipher = try CipherEditor.sharedCipher(raw: raw, key: key, organizationKey: orgKey, organizationId: organizationId)
        try await client.shareCipher(id: id, cipher: cipher, collectionIds: collectionIds)
        try await refresh()
    }

    func setCollections(_ id: String, collectionIds: [String]) async throws {
        guard let client else { throw WriteError.offline }
        try await client.setCollections(cipherId: id, collectionIds: collectionIds)
        try await refresh()
    }

    /// One request for many items: trash, restore, delete forever, archive, or move to a folder.
    enum Bulk { case trash, restore, delete, archive, move(folderId: String?) }

    func bulk(_ action: Bulk, ids: [String]) async throws {
        guard let client else { throw WriteError.offline }
        guard !ids.isEmpty else { return }
        switch action {
        case .trash: try await client.trashCiphers(ids: ids)
        case .restore: try await client.restoreCiphers(ids: ids)
        case .delete: try await client.deleteCiphers(ids: ids)
        case .archive: try await client.archiveCiphers(ids: ids)
        case .move(let folderId): try await client.moveCiphers(ids: ids, folderId: folderId)
        }
        try await refresh()
    }

    func leaveOrganization(_ id: String) async throws {
        guard let client else { throw WriteError.offline }
        try await client.leaveOrganization(id: id)
        try await refresh()
    }

    /// Changes a Send, keeping its key so the link still works.
    func updateSend(_ send: SendItem, draft: SendDraft, removePassword: Bool) async throws {
        guard let client else { throw WriteError.offline }
        let sealed = try draft.seal(userKey: userKey, keyMaterial: send.keyMaterial)
        try await client.updateSend(id: send.id, body: sealed.body)
        if removePassword { try await client.removeSendPassword(id: send.id) }
        try await refresh()
    }
}
