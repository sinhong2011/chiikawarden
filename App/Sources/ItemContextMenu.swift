import SwiftUI

/// What a right-click on an item offers, wherever the item appears (the list, One-Time Codes): copy its parts, open
/// its website, and the same actions as the detail's toolbar.
struct ItemContextMenu: View {
    @Environment(AppModel.self) private var model
    let item: VaultItem

    var body: some View {
        Group {
            if let username = item.username, !username.isEmpty {
                Button("Copy Username", systemImage: "person") { model.copy(username, label: String(localized: "Username")) }
            }
            if let password = item.password, !password.isEmpty {
                Button("Copy Password", systemImage: "key") { model.guarded(item) { model.copy(password, label: String(localized: "Password")) } }
            }
            if let totp = item.totp {
                Button("Copy One-Time Code", systemImage: "clock") { model.guarded(item) { model.copy(totp.code(at: .now), label: String(localized: "Code")) } }
            }
            if let notes = item.notes, !notes.isEmpty {
                Button("Copy Notes", systemImage: "note.text") { model.guarded(item) { model.copy(notes, label: String(localized: "Notes")) } }
            }
            if let url = websiteURL {
                Divider()
                Button("Open Website", systemImage: "safari") { NSWorkspace.shared.open(url) }
                Button("Copy Website", systemImage: "link") { model.copyPlain(url.absoluteString) }
            }
            Divider()
            if item.isDeleted {
                Button("Restore", systemImage: "arrow.uturn.backward") { Task { await model.restore(item) } }
                Button("Delete Forever…", systemImage: "trash.slash", role: .destructive) { model.confirmDeleteForever(item) }
            } else {
                Button("Edit", systemImage: "pencil") { model.guarded(item) { model.editing = EditRequest(mode: .edit(item)) } }
                Button("Clone", systemImage: "plus.square.on.square") { model.guarded(item) { model.editing = EditRequest(mode: .clone(item)) } }
                Button(item.favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: item.favorite ? "star.slash" : "star") {
                    Task { await model.toggleFavorite(item) }
                }
                Button(item.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                    Task { await model.setArchived(item, !item.isArchived) }
                }
                if item.organizationId != nil {
                    Button("Collections…", systemImage: "rectangle.stack") { model.organizationSheet = .collections(item.id) }
                } else if model.session(for: item.accountId)?.organizations.isEmpty == false {
                    Button("Move to Organization…", systemImage: "building.2") { model.organizationSheet = .share([item.id]) }
                }
                Divider()
                Button("Move to Trash…", systemImage: "trash", role: .destructive) { model.confirmTrash(item) }
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private var websiteURL: URL? {
        guard let address = item.uri ?? item.host, !address.isEmpty else { return nil }
        return URL(string: address.contains("://") ? address : "https://" + address)
    }
}
