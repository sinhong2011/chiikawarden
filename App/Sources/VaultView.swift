import AppKit
import ChiikawaCrypto
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

// Implements the "Vault window (static spec)" artboard: floating glass sidebar, rounded item list,
// dark hero card with password/code tiles, grouped detail rows.

extension Color {
    /// A color that resolves per appearance.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }

    /// Window base under all panels.
    static let windowBase = adaptive(light: Color(red: 0.945, green: 0.947, blue: 0.965), dark: Color(red: 0.105, green: 0.108, blue: 0.125))

    /// Panels floating on the window base.
    static let panel = adaptive(light: .white.opacity(0.62), dark: .white.opacity(0.05))
    static let panelStrong = adaptive(light: .white.opacity(0.78), dark: .white.opacity(0.09))
    static let panelEdge = adaptive(light: .white.opacity(0.9), dark: .white.opacity(0.08))
    static let rowSelected = adaptive(light: .white, dark: .white.opacity(0.12))
    static let hero = adaptive(light: Color(red: 0.08, green: 0.09, blue: 0.11), dark: Color(red: 0.11, green: 0.13, blue: 0.20))
}

struct VaultView: View {
    var initialSelection: VaultItem.ID?
    @Environment(AppModel.self) private var model
    @State private var showGenerator = false
    @State private var newFolderName = ""
    @State private var query = ""
    @State private var section: SidebarSelection = .section(.all)
    @State private var chip: Chip = .all

    enum Chip: CaseIterable { case all, twoFactor, favorites
        var title: LocalizedStringKey {
            switch self { case .all: "All"; case .twoFactor: "2FA"; case .favorites: "Favorites" }
        }
    }

    private var filtered: [VaultItem] {
        model.items
            .filter(section.includes)
            .filter { item in
                switch chip { case .all: true; case .twoFactor: item.hasTOTP; case .favorites: item.favorite }
            }
            .filter { item in
                query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
                    || (item.username?.localizedCaseInsensitiveContains(query) ?? false)
                    || (item.host?.localizedCaseInsensitiveContains(query) ?? false)
            }
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar(section: $section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            HStack(spacing: 8) {
                if section == .watchtower {
                    WatchtowerView { item in
                        section = .section(item.isDeleted ? .trash : .all)
                        model.selectedID = item.id
                    }
                } else {
                Group {
                    if case .account(let id) = section, !model.isUnlocked(id), let account = model.accounts.first(where: { $0.id == id }) {
                        AccountUnlockPane(account: account)
                    } else {
                        ItemColumn(items: filtered, selection: Binding(get: { model.selectedID }, set: { model.selectedID = $0 }), query: $query, chip: $chip)
                    }
                }
                    .frame(width: 300)
                Group {
                    if let item = model.selectedItem {
                        ItemDetail(item: item)
                            .id(item.id)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    } else {
                        ContentUnavailableView("No Item Selected", systemImage: "key.viewfinder")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(8)
            .background(Color.windowBase)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SearchField(query: $query)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showGenerator = true } label: { Label("Password Generator", systemImage: "dice") }
                        .help(Text("Password Generator (⌘G)"))
                        .keyboardShortcut("g", modifiers: .command)
                        .popover(isPresented: $showGenerator) { GeneratorView() }
                    Menu {
                        Button("New Login") { model.editing = EditRequest(mode: .create(.login)) }
                        Button("New Secure Note") { model.editing = EditRequest(mode: .create(.secureNote)) }
                        Button("New Card") { model.editing = EditRequest(mode: .create(.card)) }
                        Button("New Identity") { model.editing = EditRequest(mode: .create(.identity)) }
                        Button("New SSH Key") { model.editing = EditRequest(mode: .create(.sshKey)) }
                    } label: { Label("New Item", systemImage: "plus") }
                    .help(Text("New Item (⌘N)"))
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: model.selectedID)
        .sheet(item: $model.editing) { request in EditItemSheet(mode: request.mode) }
        .quickLookPreview($model.previewURL)
        .onChange(of: model.previewURL) { old, _ in
            if let old { AttachmentFiles.remove(old) } // decrypted copy only lives while previewed
        }
        .alert("New Folder", isPresented: $model.promptingNewFolder) {
            TextField("Name", text: $newFolderName, prompt: Text("e.g. Work/Servers"))
            Button("Create") { let name = newFolderName; newFolderName = ""; Task { await model.createFolder(name: name) } }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        } message: {
            Text("Use / to nest, e.g. Work/Servers.")
        }
        .overlay(alignment: .bottom) { ToastView() }
        .onAppear { if model.selectedID == nil { model.selectedID = initialSelection ?? model.items.first(where: \.favorite)?.id ?? model.items.first?.id } }
    }
}

// MARK: Sidebar

/// What the sidebar has selected: a built-in category, a folder, an organization or a collection.
enum SidebarSelection: Hashable {
    case section(VaultSection)
    case folder(String)
    case organization(String)
    case collection(String)
    case account(String)
    case watchtower

    func includes(_ item: VaultItem) -> Bool {
        switch self {
        case .watchtower: false
        case .account(let id): !item.isDeleted && item.accountId == id
        case .section(let s): s.includes(item)
        case .folder(let path): !item.isDeleted && (item.folderName == path || item.folderName?.hasPrefix(path + "/") == true)
        case .organization(let id): !item.isDeleted && item.organizationId == id
        case .collection(let id): !item.isDeleted && item.collectionIds.contains(id)
        }
    }
}

enum VaultSection: Hashable, CaseIterable {
    case all, favorites, logins, passkeys, sshKeys, cards, notes, trash

    var title: LocalizedStringKey {
        switch self {
        case .all: "All Items"; case .favorites: "Favorites"; case .logins: "Logins"; case .passkeys: "Passkeys"
        case .sshKeys: "SSH Keys"; case .cards: "Cards"; case .notes: "Secure Notes"; case .trash: "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"; case .favorites: "star"; case .logins: "key"; case .passkeys: "person.badge.key"
        case .sshKeys: "terminal"; case .cards: "creditcard"; case .notes: "note.text"; case .trash: "trash"
        }
    }

    func includes(_ item: VaultItem) -> Bool {
        if self == .trash { return item.isDeleted }
        if item.isDeleted { return false }
        switch self {
        case .trash: return true
        case .all: return true
        case .favorites: return item.favorite
        case .logins: return item.kind == .login
        case .passkeys: return item.hasPasskey
        case .sshKeys: return item.kind == .sshKey
        case .cards: return item.kind == .card
        case .notes: return item.kind == .note
        }
    }
}

/// Native macOS sidebar (system source-list style, adapts to the OS look).
private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var section: SidebarSelection

    private func count(_ selection: SidebarSelection) -> Int { model.items.filter(selection.includes).count }

    var body: some View {
        List(selection: Binding(get: { section }, set: { if let s = $0 { section = s } })) {
            Section("Vault") {
                ForEach(VaultSection.allCases, id: \.self) { s in
                    Label(s.title, systemImage: s.symbol)
                        .badge(count(.section(s)))
                        .tag(SidebarSelection.section(s))
                }
                Label("Watchtower", systemImage: "checkmark.shield")
                    .badge(model.watchtowerIssueCount)
                    .tag(SidebarSelection.watchtower)
            }
            if !model.folders.isEmpty {
                Section("Folders") {
                    ForEach(FolderNode.tree(model.folders)) { node in
                        FolderRow(node: node, count: count)
                    }
                }
            }
            if model.accounts.count > 1 {
                Section("Accounts") {
                    ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                        let unlocked = model.isUnlocked(account.id)
                        HStack(spacing: 8) {
                            Circle().fill(AccountColor.color(index)).frame(width: 9, height: 9)
                            Text(verbatim: account.email).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            if !unlocked { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
                        }
                        .badge(unlocked ? count(.account(account.id)) : 0)
                        .help(Text(verbatim: account.serverSummary))
                        .tag(SidebarSelection.account(account.id))
                        .contextMenu {
                            if unlocked { Button("Lock") { model.lock(account.id) } }
                            Button("Log Out…", role: .destructive) { model.logOut(account.id) }
                        }
                    }
                    Button { model.beginAddAccount() } label: { Label("Add Account…", systemImage: "plus") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(model.organizations) { org in
                Section(org.name) {
                    Label("All Items", systemImage: "building.2")
                        .badge(count(.organization(org.id)))
                        .tag(SidebarSelection.organization(org.id))
                    ForEach(org.children) { collection in
                        Label(collection.name, systemImage: "rectangle.stack")
                            .badge(count(.collection(collection.id)))
                            .tag(SidebarSelection.collection(collection.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: model.serverDisplayName.isEmpty ? "vault" : model.serverDisplayName)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    SyncStatusText().font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { model.lock() } label: { Image(systemName: "lock").accessibilityLabel(Text("Lock")) }
                    .buttonStyle(.borderless)
                    .help(Text("Lock Vault"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct SyncStatusText: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isSyncing {
            Text("Syncing…")
        } else if let date = model.lastSynced {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if context.date.timeIntervalSince(date) < 60 {
                    Text("Synced just now")
                } else {
                    Text("Synced \(date, format: .relative(presentation: .named))")
                }
            }
        } else {
            Text("Offline · saved vault")
        }
    }
}

// MARK: Folders

/// A folder in the sidebar tree. "Work/Servers" nests under "Work"; parents without a real folder are virtual.
struct FolderNode: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    var folderIds: [String] = []
    var children: [FolderNode] = []

    static func tree(_ folders: [Grouping]) -> [FolderNode] {
        var roots: [FolderNode] = []
        for folder in folders {
            let parts = folder.name.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !parts.isEmpty else { continue }
            insert(parts[...], prefix: "", folderId: folder.id, into: &roots)
        }
        return sorted(roots)
    }

    private static func insert(_ parts: ArraySlice<String>, prefix: String, folderId: String, into nodes: inout [FolderNode]) {
        guard let head = parts.first else { return }
        let path = prefix.isEmpty ? head : prefix + "/" + head
        var index = nodes.firstIndex { $0.path == path }
        if index == nil { nodes.append(FolderNode(path: path, name: head)); index = nodes.count - 1 }
        if parts.count == 1 { nodes[index!].folderIds.append(folderId) } else {
            insert(parts.dropFirst(), prefix: path, folderId: folderId, into: &nodes[index!].children)
        }
    }

    private static func sorted(_ nodes: [FolderNode]) -> [FolderNode] {
        nodes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { var n = $0; n.children = sorted(n.children); return n }
    }
}

/// Recursive folder row; items dropped on a real folder move into it.
private struct FolderRow: View {
    @Environment(AppModel.self) private var model
    let node: FolderNode
    let count: (SidebarSelection) -> Int
    @State private var expanded = true
    @State private var targeted = false

    var body: some View {
        let label = Label(node.name, systemImage: node.folderIds.isEmpty ? "folder.badge.questionmark" : "folder")
            .badge(count(.folder(node.path)))
            .tag(SidebarSelection.folder(node.path))
            .listRowBackground(targeted ? Color.brand.opacity(0.18).clipShape(.rect(cornerRadius: 6)) : nil)
            .dropDestination(for: String.self) { ids, _ in
                guard !node.folderIds.isEmpty else { return false }
                Task { await model.move(itemIDs: ids, toFolderIn: node.folderIds) }
                return true
            } isTargeted: { targeted = $0 }
        if node.children.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(node.children) { FolderRow(node: $0, count: count) }
            } label: { label }
        }
    }
}

// MARK: Search

/// Centered toolbar search, ⌘F to focus.
private struct SearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search vault", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { query = ""; focused = false }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary).accessibilityLabel(Text("Clear search")) }
                    .buttonStyle(.plain)
                    .help(Text("Clear"))
            } else {
                Text(verbatim: "⌘F").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 380, height: 30)
        .background(Color.panelStrong, in: .capsule)
        .overlay(Capsule().strokeBorder(focused ? Color.brand.opacity(0.6) : Color.panelEdge, lineWidth: focused ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: focused)
        .background {
            Button("") { focused = true }.keyboardShortcut("f", modifiers: .command).hidden()
        }
    }
}

// MARK: Item column

private struct ItemColumn: View {
    let items: [VaultItem]
    @Binding var selection: VaultItem.ID?
    @Binding var query: String
    @Binding var chip: VaultView.Chip

    private func step(_ delta: Int, _ proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : items.count)
        let next = items[min(max(current + delta, 0), items.count - 1)].id
        selection = next
        proxy.scrollTo(next)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(VaultView.Chip.allCases, id: \.self) { c in
                    Button { withAnimation(.snappy(duration: 0.2)) { chip = c } } label: {
                        Text(c.title).font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).frame(height: 28)
                            .foregroundStyle(chip == c ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.primary))
                            .background(chip == c ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.panelStrong), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        ItemRow(item: item, isSelected: item.id == selection, highlight: query)
                            .onTapGesture { selection = item.id }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(item.id == selection ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { selection = item.id }
                            .draggable(item.id) { ItemRow(item: item, isSelected: true).frame(width: 260) }
                    }
                }
                .padding(6)
            }
            // ↑/↓ move the selection; the search field hands focus here with ↓ too.
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { step(1, proxy); return .handled }
            .onKeyPress(.upArrow) { step(-1, proxy); return .handled }
            }
            .scrollIndicators(.never)
            .background(Color.panel, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "No Items" : "No Results", systemImage: "tray")
                }
            }
        }
        .padding(.horizontal, 6)
    }
}

struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: VaultItem
    var isSelected = false
    /// Search text to highlight in the name and username.
    var highlight = ""
    @State private var hovered = false

    /// Account colour, only when more than one account is open.
    private var accountDot: Color? {
        guard model.sessions.count > 1, let i = model.accounts.firstIndex(where: { $0.id == item.accountId }) else { return nil }
        return AccountColor.color(i)
    }

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(item: item, size: 38)
                .overlay(alignment: .bottomTrailing) {
                    if let accountDot {
                        Circle().fill(accountDot).frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Color.windowBase, lineWidth: 2))
                            .offset(x: 3, y: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(Highlight.marked(item.name, highlight)).font(.system(size: 14, weight: .bold)).lineLimit(1)
                if let username = item.username {
                    Text(Highlight.marked(username, highlight)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if item.hasTOTP {
                Text(verbatim: "2FA").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color.brand)
            }
        }
        .padding(9)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.rowSelected)
                    .shadow(color: .black.opacity(0.12), radius: 9, y: 6)
            } else if hovered {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.primary.opacity(0.04))
            }
        }
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .animation(.snappy(duration: 0.18), value: isSelected)
    }
}

// MARK: Detail

struct ItemDetail: View {
    @Environment(AppModel.self) private var model
    let item: VaultItem
    @State private var revealToggle = false
    @State private var confirmDelete = false
    @State private var dropping = false
    /// Revealed while toggled on, or while ⌥ is held.
    private var reveal: Binding<Bool> {
        Binding(get: { revealToggle || model.optionHeld }, set: { revealToggle = $0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    HStack(spacing: 0) {
                        if item.isDeleted {
                            toolbarButton("arrow.uturn.backward", help: "Restore") { Task { await model.restore(item) } }
                            toolbarButton("trash.slash", help: "Delete Forever") { confirmDelete = true }
                                .foregroundStyle(.red)
                        } else {
                            toolbarButton(item.favorite ? "star.fill" : "star", help: "Favorite") { Task { await model.toggleFavorite(item) } }
                                .foregroundStyle(item.favorite ? .yellow : .primary)
                            toolbarButton("pencil", help: "Edit (⌘E)") { model.editing = EditRequest(mode: .edit(item)) }
                            toolbarButton("trash", help: "Move to Trash (⌘⌫)") { Task { await model.trash(item) } }
                        }
                    }
                    .padding(3)
                    .background(Color.panelStrong, in: .capsule)
                    .overlay(Capsule().strokeBorder(Color.panelEdge))
                }

                if item.isDeleted {
                    Label("In Trash. Restore it to use it again, or delete it forever.", systemImage: "trash")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HeroCard(item: item, reveal: reveal)

                if !item.fields.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(item.fields.enumerated()), id: \.element.id) { index, field in
                            FieldLine(field: field, reveal: reveal.wrappedValue)
                                .overlay(alignment: .top) { if index > 0 { Divider().opacity(0.6).padding(.leading, 16) } }
                        }
                    }
                    .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))
                }

                VStack(spacing: 0) {
                    if let orgId = item.organizationId, let org = model.organizations.first(where: { $0.id == orgId }) {
                        DetailRow(symbol: "building.2", title: "Organization") {
                            let names = org.children.filter { item.collectionIds.contains($0.id) }.map(\.name)
                            Text(verbatim: ([org.name] + names).joined(separator: " › ")).foregroundStyle(.secondary)
                        }
                    } else if let folderId = item.folderId, let folder = model.folders.first(where: { $0.id == folderId }) {
                        DetailRow(symbol: "folder", title: "Folder") {
                            Text(verbatim: folder.name).foregroundStyle(.secondary)
                        }
                    }
                    if item.hasPasskey {
                        DetailRow(symbol: "person.badge.key", title: "Passkey") {
                            if let pk = item.passkeys.first {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(verbatim: [pk.userName, pk.rpId].compactMap { $0 }.joined(separator: " · "))
                                    if pk.creationDate > .distantPast {
                                        Text("Created \(pk.creationDate.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                                    }
                                }
                                .foregroundStyle(.secondary)
                            } else {
                                Text("Stored with a key type Chiikawarden can't use").foregroundStyle(.secondary)
                            }
                        }
                    }
                    if item.password != nil {
                        DetailRow(symbol: "checkmark.shield", title: "Watchtower") {
                            HStack(spacing: 7) {
                                Circle().fill(health.tint).frame(width: 7, height: 7)
                                Text(health.text)
                            }
                        }
                    }
                    if let notes = item.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                .textCase(.uppercase).tracking(0.6)
                            Text(verbatim: notes).font(.system(size: 13)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .overlay(alignment: .top) { Divider().opacity(0.6) }
                    }
                }
                .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))

                if !item.attachments.isEmpty || !item.isDeleted {
                    AttachmentsSection(item: item)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .dropDestination(for: URL.self) { urls, _ in
            guard !item.isDeleted, !urls.isEmpty else { return false }
            Task { await model.addAttachments(urls, to: item) }
            return true
        } isTargeted: { dropping = $0 }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.brand, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(Color.brand.opacity(0.06), in: .rect(cornerRadius: 18, style: .continuous))
                    .overlay {
                        Label("Drop to attach", systemImage: "paperclip")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.brand)
                    }
                    .padding(10)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: dropping)
        .confirmationDialog("Delete “\(item.name)” forever?", isPresented: $confirmDelete) {
            Button("Delete Forever", role: .destructive) { Task { await model.deleteForever(item) } }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var health: (text: LocalizedStringKey, tint: Color) {
        guard let pw = item.password else { return ("", .secondary) }
        if item.reuseCount > 0 { return ("Reused in \(item.reuseCount + 1) items", .orange) }
        let classes = [pw.contains(where: \.isLowercase), pw.contains(where: \.isUppercase),
                       pw.contains(where: \.isNumber), pw.contains { !$0.isLetter && !$0.isNumber }].filter { $0 }.count
        if pw.count < 10 || classes < 3 { return ("Weak password", .red) }
        return ("Strong · unique", .green)
    }

    private func toolbarButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 34, height: 30).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }
}

private struct HeroCard: View {
    @Environment(AppModel.self) private var model
    let item: VaultItem
    @Binding var reveal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Text(item.name.prefix(1).uppercased())
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.14), in: .rect(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white.opacity(0.25)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 30, weight: .heavy)).tracking(-0.8).lineLimit(1)
                    Text(verbatim: [item.username, item.host].compactMap { $0 }.joined(separator: " · "))
                        .foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                if let password = item.password {
                    Tile {
                        model.copy(password, label: String(localized: "Password"))
                    } content: {
                        Text("Password · click to copy").font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                        Text(verbatim: reveal ? password : String(repeating: "•", count: 12))
                            .font(.system(size: 16, design: .monospaced))
                            .tracking(reveal ? 0.5 : 3)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                }
                if let totp = item.totp {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let code = totp.code(at: context.date)
                        let left = totp.secondsRemaining(at: context.date)
                        let period = Double(totp.period)
                        let remaining = 1 - context.date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
                        Tile {
                            model.copy(code, label: String(localized: "Code"))
                        } content: {
                            HStack {
                                Text("One-time code")
                                Spacer()
                                Text(verbatim: "\(left)s").monospacedDigit()
                            }
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                            Text(verbatim: code.prefix(code.count / 2) + " " + code.suffix(code.count - code.count / 2))
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .contentTransition(.numericText())
                            GeometryReader { g in
                                Capsule().fill(.white.opacity(0.15))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(left <= 5 ? Color.orange : Color.white)
                                            .frame(width: g.size.width * remaining)
                                    }
                            }
                            .frame(height: 4)
                        }
                        .animation(.snappy, value: code)
                    }
                }
            }

            HStack(spacing: 8) {
                if let host = item.host, let url = URL(string: "https://\(host)") {
                    Link(destination: url) {
                        Label("Open website", systemImage: "arrow.up.right.square")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.hero)
                            .padding(.horizontal, 18).frame(height: 40)
                            .background(.white, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                if item.password != nil || item.fields.contains(where: \.secret) {
                    Button { withAnimation(.snappy) { reveal.toggle() } } label: {
                        Label(reveal ? "Hide" : "Reveal", systemImage: reveal ? "eye.slash" : "eye")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 18).frame(height: 40)
                            .background(.white.opacity(0.14), in: .capsule)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.hero
                RadialGradient(colors: [Color.brand.opacity(0.55), .clear],
                               center: UnitPoint(x: 0.95, y: -0.1), startRadius: 0, endRadius: 280)
            }
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 16)
    }
}

private struct Tile<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) { content }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.12), in: .rect(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.18)))
                .contentShape(.rect)
        }
        .buttonStyle(PressScale())
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A label/value row with copy; secrets stay masked until revealed.
private struct FieldLine: View {
    @Environment(AppModel.self) private var model
    let field: ItemField
    let reveal: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: field.label)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(verbatim: field.secret && !reveal ? String(repeating: "•", count: 10) : field.value)
                .font(.system(size: 13, design: field.monospaced ? .monospaced : .default))
                .lineLimit(field.monospaced ? 3 : 2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
            Button { model.copy(field.value, label: field.label) } label: { Image(systemName: "doc.on.doc").accessibilityLabel(Text("Copy \(field.label)")) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(Text("Copy"))
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}

private struct DetailRow<Value: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            value.font(.system(size: 13))
        }
        .padding(.horizontal, 16).frame(minHeight: 46)
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Color.hero, in: .capsule)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 10)
                    .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.9)).combined(with: .opacity))
            }
        }
        .padding(.bottom, 28)
        .animation(.spring(duration: 0.35, bounce: 0.35), value: model.toast)
    }
}

/// Colored initial tile; color is derived from the name so it stays stable.
struct Monogram: View {
    let name: String
    let size: CGFloat

    private static let palette: [Color] = [
        Color(red: 0.14, green: 0.16, blue: 0.18), Color(red: 0.96, green: 0.51, blue: 0.13), Color(red: 0.43, green: 0.29, blue: 1),
        Color(red: 0.18, green: 0.64, blue: 0.42), Color(red: 0.24, green: 0.51, blue: 0.96), Color(red: 0.89, green: 0.26, blue: 0.16),
        Color(red: 0.23, green: 0.27, blue: 0.32), Color(red: 0.91, green: 0.64, blue: 0.24),
    ]

    var body: some View {
        let hue = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        Text(name.prefix(1).uppercased())
            .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.palette[abs(hue) % Self.palette.count], in: .rect(cornerRadius: size * 0.29, style: .continuous))
    }
}

/// Unlock one locked account in place (from the sidebar), without leaving the vault.
private struct AccountUnlockPane: View {
    @Environment(AppModel.self) private var model
    let account: SavedAccount
    @State private var password = ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 24)).foregroundStyle(.secondary)
            Text("Account locked").font(.system(size: 16, weight: .semibold))
            Text(verbatim: "\(account.email) · \(account.serverSummary)")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if model.isTouchIDEnabled(account.id) {
                Button { Task { await model.unlockWithTouchID() } } label: { Label("Unlock with Touch ID", systemImage: "touchid") }
            }
            SecureField("Master password", text: $password)
                .textFieldStyle(SoftFieldStyle())
                .frame(width: 240)
                .onSubmit { submit() }
            if let error = model.errorMessage {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
            }
            Button("Unlock") { submit() }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || model.isBusy)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.panel, in: .rect(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 6)
    }

    private func submit() {
        Task {
            await model.unlock(password: password, accountId: account.id)
            if model.isUnlocked(account.id) { password = "" }
        }
    }
}

/// Marks every case/diacritic-insensitive occurrence of `query` with a tinted background.
enum Highlight {
    static func marked(_ text: String, _ query: String) -> AttributedString {
        var out = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return out }
        var start = text.startIndex
        while let range = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex) {
            if let r = Range(range, in: out) {
                out[r].backgroundColor = Color.brand.opacity(0.22)
                out[r].foregroundColor = .primary
            }
            start = range.upperBound
        }
        return out
    }
}

/// Files on an item: Quick Look, Save As, delete; add with the button or by dropping files on the item.
private struct AttachmentsSection: View {
    @Environment(AppModel.self) private var model
    let item: VaultItem
    @State private var pendingDelete: VaultItem.Attachment?
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Attachments").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .textCase(.uppercase).tracking(0.6)
                Spacer()
                if model.attachmentBusy.contains(item.id) { ProgressView().controlSize(.small) }
                if !item.isDeleted {
                    Button { choosing = true } label: { Label("Add Files…", systemImage: "plus") }
                        .buttonStyle(.borderless).font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if item.attachments.isEmpty {
                Text("Drop files here to attach them, encrypted.")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 16).padding(.bottom, 14)
            }
            ForEach(item.attachments) { file in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (file.fileName as NSString).pathExtension) ?? .data))
                        .resizable().frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: file.fileName).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text(verbatim: file.sizeName).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.attachmentBusy.contains(file.id) {
                        ProgressView().controlSize(.small)
                    }
                    Button { Task { await model.previewAttachment(file, of: item) } } label: {
                        Image(systemName: "eye").accessibilityLabel(Text("Quick Look"))
                    }
                    .help(Text("Quick Look"))
                    Button { Task { await model.saveAttachment(file, of: item) } } label: {
                        Image(systemName: "square.and.arrow.down").accessibilityLabel(Text("Save As…"))
                    }
                    .help(Text("Save As…"))
                    if !item.isDeleted {
                        Button { pendingDelete = file } label: {
                            Image(systemName: "trash").accessibilityLabel(Text("Delete"))
                        }
                        .help(Text("Delete"))
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .overlay(alignment: .top) { Divider().opacity(0.6) }
                .contentShape(.rect)
                .onTapGesture(count: 2) { Task { await model.previewAttachment(file, of: item) } }
            }
        }
        .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await model.addAttachments(urls, to: item) } }
        }
        .confirmationDialog("Delete “\(pendingDelete?.fileName ?? "")”?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let file = pendingDelete { Task { await model.deleteAttachment(file, of: item) } }
            }
        } message: {
            Text("The file is removed from your vault on every device.")
        }
    }
}
