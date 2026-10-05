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
    static let hero = adaptive(light: Color(red: 0.08, green: 0.09, blue: 0.11), dark: Color(red: 0.15, green: 0.16, blue: 0.19))
}

struct VaultView: View {
    var initialSelection: VaultItem.ID?
    /// Narrow windows: the strip's starting pane (snapshots and previews).
    var initialDepth = 1
    @Environment(AppModel.self) private var model
    @State private var newFolderName = ""
    @State private var query = ""
    @State private var section: SidebarSelection = .section(.all)
    @State private var chip: Chip = .all
    /// Window width, to adapt from three columns down to a single phone-width column.
    @State private var width: CGFloat = 1120
    @State private var columns = NavigationSplitViewVisibility.all
    /// Narrow windows: which pane of the strip is in view (0 sidebar, 1 list or page, 2 detail).
    @State private var depth = 1

    /// Below this width the sidebar, list and detail become one sliding strip (Reeder-style).
    private var compact: Bool { width < 900 }
    private var isItemSection: Bool { ![.codes, .generator, .sends, .watchtower].contains(section) }
    private var maxDepth: Int { isItemSection ? (model.selectedItem == nil ? 1 : 2) : 1 }

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
        // Measure the space the window offers (not the content, which may refuse to shrink) and lay out for it.
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .onChange(of: geo.size.width, initial: true) { old, new in resized(from: initialMeasure ? 1120 : old, to: new) }
        }
    }

    @State private var initialMeasure = true
    @State private var appliedInitialDepth = false

    private func resized(from old: CGFloat, to new: CGFloat) {
        initialMeasure = false
        width = new
        if !appliedInitialDepth { appliedInitialDepth = true; depth = initialDepth }
        // Fold the sidebar away as the window narrows; bring it back when it widens again.
        if new < 900, old >= 900 { columns = .detailOnly }
        if new >= 900, old < 900 { columns = .all }
    }

    // MARK: Panes

    private var compactPanes: [AnyView] {
        let sidebar = AnyView(sidebarPane)
        guard isItemSection else { return [sidebar, AnyView(sectionPane)] }
        return [sidebar, AnyView(listPane), AnyView(detailPane.environment(\.showsDetailToolbar, depth == 2))]
    }

    /// The sidebar as a pane on the narrow-window strip: the same list, on the app's panel.
    private var sidebarPane: some View {
        Sidebar(section: $section)
            .scrollContentBackground(.hidden)
            .background(Color.panel, in: .rect(cornerRadius: 22, style: .continuous))
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder private var sectionPane: some View {
        switch section {
        case .codes: CodesPane()
        case .generator: GeneratorPane()
        case .sends: SendsPane()
        default:
            WatchtowerView { item in
                section = .section(item.isDeleted ? .trash : .all)
                model.selectedID = item.id
                if compact { depth = 2 }
            }
        }
    }

    @ViewBuilder private var listPane: some View {
        if case .account(let id) = section, !model.isUnlocked(id), let account = model.accounts.first(where: { $0.id == id }) {
            AccountUnlockPane(account: account)
        } else {
            ItemColumn(items: filtered, selection: Binding(get: { model.selectedID }, set: { id in
                model.selectedID = id
                if compact, id != nil { depth = 2 } // tapping an item slides to it
            }), query: $query, chip: $chip)
        }
    }

    @ViewBuilder private var detailPane: some View {
        if let item = model.selectedItem {
            ItemDetail(item: item)
                .id(item.id)
                .transition(.opacity.combined(with: .offset(y: 8)))
        } else {
            ContentUnavailableView("No Item Selected", systemImage: "key.viewfinder")
        }
    }

    private var content: some View {
        @Bindable var model = model
        return NavigationSplitView(columnVisibility: $columns) {
            Sidebar(section: $section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                // Narrow windows navigate with the strip's own back button; one sidebar control is enough.
                .toolbar(removing: compact ? .sidebarToggle : nil)
        } detail: {
            Group {
                if compact {
                    PaneStrip(panes: compactPanes, depth: $depth, maxDepth: maxDepth)
                } else if isItemSection {
                    HStack(spacing: 8) {
                        listPane.frame(width: 300)
                        detailPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    sectionPane
                }
            }
            .padding(8)
            .background(WindowBackdrop())
            .toolbar(removing: .title)
            .toolbar {
                // Search and + live in the header, over the item list (Liquid layout).
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 8) {
                        if compact && depth > 0 {
                            Button { depth = max(depth - 1, 0) } label: {
                                Image(systemName: depth == 1 ? "sidebar.left" : "chevron.left").font(.system(size: 14, weight: .medium))
                                    .contentTransition(.symbolEffect(.replace))
                                    .frame(width: 36, height: 36).contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                            .modifier(HeaderChrome(shape: .circle))
                            .keyboardShortcut("[", modifiers: .command)
                            .help(Text("Back (⌘[)"))
                            .accessibilityLabel(Text("Back"))
                        }
                        // On a phone-width detail, the header belongs to the item's actions (search and + are the list's).
                        if !(compact && width < PaneStrip.pairWidth && depth == 2) {
                            PaletteTrigger().frame(width: width < 560 ? 150 : 228)
                            NewItemButton()
                        }
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .background {
                // Keyboard: ⌘K / ⌘F open the command palette, ⌘G the generator.
                Group {
                    Button("") { model.openPalette() }.keyboardShortcut("k", modifiers: .command)
                    Button("") { model.openPalette() }.keyboardShortcut("f", modifiers: .command)
                    Button("") { section = .generator }.keyboardShortcut("g", modifiers: .command)
                }
                .hidden()
            }
        }
        .animation(.snappy(duration: 0.25), value: model.selectedID)
        .onChange(of: section) { if compact { depth = 1 } } // picked a section: slide to it
        .onChange(of: model.selectedItem == nil) { _, none in if none, depth == 2 { depth = 1 } }
        // The system sidebar toggle on a narrow window: show the strip's sidebar pane instead.
        .onChange(of: columns) { _, new in
            if compact, new != .detailOnly { columns = .detailOnly; depth = 0 }
        }
        // When the selected item leaves the list (trashed, restored, deleted, filtered out), select its neighbour
        // so the list and the detail never disagree.
        .onChange(of: filtered.map(\.id)) { old, new in
            guard let selected = model.selectedID, !new.contains(selected) else { return }
            let at = old.firstIndex(of: selected) ?? 0
            model.selectedID = new.isEmpty ? nil : new[min(at, new.count - 1)]
        }
        .onChange(of: model.requestedSection) { _, requested in
            if let requested { section = requested; model.requestedSection = nil }
        }
        .onChange(of: model.showingGenerator) { _, show in
            if show { section = .generator; model.showingGenerator = false }
        }
        .sheet(item: $model.editing) { request in EditItemSheet(mode: request.mode) }
        .sheet(item: $model.transfer) { transfer in
            switch transfer {
            case .export: ExportSheet()
            case .importFile(let url): ImportSheet(initialFile: url)
            }
        }
        // Drop an export file (from any supported app) on the window to import it.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, ["csv", "json"].contains(url.pathExtension.lowercased()), !model.sessions.isEmpty else { return false }
            model.beginImport(url)
            return true
        }
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
    case sends
    case generator
    case codes

    func includes(_ item: VaultItem) -> Bool {
        switch self {
        case .watchtower, .sends, .generator, .codes: false
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
                Label("Send", systemImage: "paperplane")
                    .badge(model.sends.count)
                    .tag(SidebarSelection.sends)
                Label("One-Time Codes", systemImage: "clock.badge.checkmark")
                    .badge(model.items.filter { !$0.isDeleted && $0.totp != nil }.count)
                    .tag(SidebarSelection.codes)
                Label("Generator", systemImage: "dice")
                    .tag(SidebarSelection.generator)
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
                            Group {
                                if unlocked { Button("Lock", systemImage: "lock") { model.lock(account.id) } }
                                Button("Log Out…", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { model.confirmLogOut(account.id) }
                            }
                            .labelStyle(.titleAndIcon)
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
        .safeAreaInset(edge: .bottom) { SidebarAccountCard().padding(10) }
    }
}

/// Who's signed in, where, and how fresh the vault is — with sync and lock at hand and the rest in a menu.
private struct SidebarAccountCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    private var email: String {
        let name = model.sessions.count == 1 ? model.sessions[0].account.email : model.serverDisplayName
        return name.isEmpty ? String(localized: "Vault") : name
    }
    private var host: String {
        let hosts = Set(model.sessions.compactMap { $0.environment?.displayHost })
        return hosts.count == 1 ? hosts.first! : model.serverDisplayName
    }
    private var webVault: URL? {
        guard model.sessions.count == 1, let env = model.sessions[0].environment else { return nil }
        return switch env {
        case .bitwardenUS: URL(string: "https://vault.bitwarden.com")
        case .bitwardenEU: URL(string: "https://vault.bitwarden.eu")
        case .selfHosted(let base): base
        case .custom(let urls): urls.webVault ?? urls.base
        }
    }

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 10) {
            Menu {
                Group {
                Section {
                    Label { Text(verbatim: email) } icon: { Image(systemName: "person.crop.circle") }
                    if !host.isEmpty { Label { Text(verbatim: host) } icon: { Image(systemName: "server.rack") } }
                }
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") { sync() }
                if let webVault {
                    Button("Open Web Vault", systemImage: "safari") { NSWorkspace.shared.open(webVault) }
                }
                if !host.isEmpty {
                    Button("Copy Server Address", systemImage: "doc.on.doc") { model.copy(host, label: String(localized: "Server")) }
                }
                Divider()
                Button("Import…", systemImage: "square.and.arrow.down") { model.beginImport() }
                Button("Export Vault…", systemImage: "square.and.arrow.up") { model.beginExport() }
                Divider()
                Button("Add Account…", systemImage: "person.badge.plus") { model.beginAddAccount() }
                Button("Settings…", systemImage: "gearshape") { model.showSettings() }
                Divider()
                Button("Lock Vault", systemImage: "lock") { model.lock() }
                Button("Log Out…", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    model.confirmLogOut(model.sessions.count == 1 ? model.sessions[0].account.id : nil)
                }
                }
                .labelStyle(.titleAndIcon) // macOS menus drop icons unless asked
            } label: {
                HStack(spacing: 10) {
                    Monogram(name: email, size: 30)
                        .overlay(alignment: .bottomTrailing) {
                            Circle().fill(model.isSyncing ? Color.secondary : Color.brandFill)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().strokeBorder(dark ? Color.black.opacity(0.6) : .white, lineWidth: 1.5))
                                .offset(x: 2, y: 2)
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: email).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        SyncStatusText().font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Account"))
                .accessibilityValue(Text(verbatim: email))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help(Text(verbatim: host))
            .accessibilityLabel(Text("Account"))

            footerButton("arrow.triangle.2.circlepath", help: "Sync Now", spinning: model.isSyncing) { sync() }
            footerButton("lock", help: "Lock Vault") { model.lock() }
        }
        .padding(.leading, 8).padding(.trailing, 6).padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(dark ? Color.white.opacity(hovering ? 0.09 : 0.06) : Color.white.opacity(hovering ? 0.75 : 0.55))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(dark ? 0.08 : 0.05)))
        }
        .onHover { h in withAnimation(.snappy(duration: 0.15)) { hovering = h } }
    }

    private func sync() { Task { try? await model.refresh() } }

    private func footerButton(_ symbol: String, help: LocalizedStringKey, spinning: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolEffect(.rotate, isActive: spinning)
                .frame(width: 26, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(HeaderIconStyle())
        .disabled(spinning)
        .help(Text(help))
        .accessibilityLabel(Text(help))
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
/// Looks like a search field; opens the command palette (⌘K / ⌘F).
private struct PaletteTrigger: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button { model.openPalette() } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium))
                Text("Search").font(.system(size: 13))
                Spacer()
                Text(verbatim: "⌘K")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 4))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .modifier(HeaderChrome(shape: .capsule, hovering: hovering))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text("Search or run a command (⌘K)"))
        .accessibilityLabel(Text("Search or run a command"))
    }
}

/// The round + next to search: new items of every kind.
private struct NewItemButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Group {
                Button("New Login", systemImage: "key") { model.editing = EditRequest(mode: .create(.login)) }
                Button("New Secure Note", systemImage: "note.text") { model.editing = EditRequest(mode: .create(.secureNote)) }
                Button("New Card", systemImage: "creditcard") { model.editing = EditRequest(mode: .create(.card)) }
                Button("New Identity", systemImage: "person.text.rectangle") { model.editing = EditRequest(mode: .create(.identity)) }
                Button("New SSH Key", systemImage: "terminal") { model.editing = EditRequest(mode: .create(.sshKey)) }
                Divider()
                Button("New Folder…", systemImage: "folder.badge.plus") { model.promptingNewFolder = true }
            }
            .labelStyle(.titleAndIcon)
        } label: {
            Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .modifier(HeaderChrome(shape: .circle))
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("New Item (⌘N)"))
        .accessibilityLabel(Text("New Item"))
    }
}

/// Sidebar › Generator: passwords, passphrases and usernames as a page.
private struct GeneratorPane: View {
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                GeneratorView()
                    .padding(28)
                    .frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            }
            .scrollIndicators(.never)
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
                LazyVStack(spacing: 6) {
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
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.brand)
                    .help(Text("Has a one-time code"))
                    .accessibilityLabel(Text("Has a one-time code"))
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

extension EnvironmentValues {
    /// False while the detail pane sits off-screen on the narrow-window strip.
    @Entry var showsDetailToolbar = true
}

struct ItemDetail: View {
    @Environment(\.showsDetailToolbar) private var showsToolbar
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
                    if item.kind == .sshKey, let publicKey = item.properties["publicKey"], !publicKey.isEmpty {
                        DetailRow(symbol: "signature", title: "Git signing") {
                            Button("Copy Setup") {
                                model.copyPlain("""
                                git config --global gpg.format ssh
                                git config --global user.signingkey "key::\(publicKey)"
                                git config --global commit.gpgsign true
                                """)
                            }
                            .buttonStyle(.borderless)
                            .help(Text("Commands that make git sign commits with this key through the Chiikawarden SSH agent"))
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
        .toolbar {
            // Item actions sit in the header, top right (Liquid layout) — only while this detail is in view.
            if showsToolbar {
                ToolbarSpacer(.flexible)
                ToolbarItem { actions }
                    .sharedBackgroundVisibility(.hidden)
            }
        }
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

    private var actions: some View {
        HStack(spacing: 0) {
            if item.isDeleted {
                toolbarButton("arrow.uturn.backward", help: "Restore") { Task { await model.restore(item) } }
                toolbarButton("trash.slash", help: "Delete Forever") { confirmDelete = true }
                    .foregroundStyle(.red)
            } else {
                if let host = item.host, let url = URL(string: "https://\(host)") {
                    toolbarButton("arrow.up.right.square", help: "Open website") { NSWorkspace.shared.open(url) }
                }
                if item.password != nil || item.fields.contains(where: \.secret) {
                    toolbarButton(reveal.wrappedValue ? "eye.slash" : "eye", help: reveal.wrappedValue ? "Hide" : "Reveal (hold ⌥)",
                                  spoken: reveal.wrappedValue ? "Hide" : "Reveal") {
                        withAnimation(.snappy) { reveal.wrappedValue.toggle() }
                    }
                }
                if item.host != nil || item.password != nil {
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 3)
                }
                toolbarButton(item.favorite ? "star.fill" : "star", help: "Favorite") { Task { await model.toggleFavorite(item) } }
                    .foregroundStyle(item.favorite ? .yellow : .primary)
                toolbarButton("pencil", help: "Edit (⌘E)", spoken: "Edit") { model.editing = EditRequest(mode: .edit(item)) }
                toolbarButton("trash", help: "Move to Trash (⌘⌫)", spoken: "Move to Trash") { model.confirmTrash(item) }
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 32)
        .modifier(HeaderChrome(shape: .capsule))
    }

    /// `spoken`: the VoiceOver label when the tooltip carries a shortcut hint, e.g. "Edit" for "Edit (⌘E)".
    private func toolbarButton(_ symbol: String, help: LocalizedStringKey, spoken: LocalizedStringKey? = nil,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 30, height: 26).contentShape(.rect)
        }
        .buttonStyle(HeaderIconStyle())
        .help(Text(help))
        .accessibilityLabel(Text(spoken ?? help))
    }
}

extension HeroCard {
    /// The password and one-time-code tiles.
    @ViewBuilder func tiles(_ style: HeroStyle) -> some View {
                if let password = item.password {
                    Tile(style: style) {
                        model.copy(password, label: String(localized: "Password"))
                    } content: {
                        let strength = StrengthMeter(password: password).level
                        HStack {
                            Text("Password · click to copy").lineLimit(1)
                            Spacer(minLength: 6)
                            Text(strength.1)
                        }
                        .font(.system(size: 12)).foregroundStyle(style.muted)
                        Text(verbatim: reveal ? password : String(repeating: "•", count: 12))
                            .font(.system(size: reveal ? 16 : 20, weight: .semibold, design: .monospaced))
                            .tracking(reveal ? 0.5 : 2)
                            .lineLimit(1)
                            .frame(height: 24, alignment: .leading)
                            .contentTransition(.opacity)
                        // Same place and size as the code's countdown bar, so the tiles line up.
                        LevelBar(level: strength.0, color: strength.0 <= 1 ? .red : strength.0 == 2 ? .orange : .green)
                    }
                }
                if let totp = item.totp {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let code = totp.code(at: context.date)
                        let left = totp.secondsRemaining(at: context.date)
                        let period = Double(totp.period)
                        let remaining = 1 - context.date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
                        Tile(style: style) {
                            model.copy(code, label: String(localized: "Code"))
                        } content: {
                            HStack {
                                Text("One-time code")
                                Spacer()
                                Text(verbatim: "\(left)s").monospacedDigit()
                            }
                            .font(.system(size: 12)).foregroundStyle(style.muted)
                            Text(verbatim: code.prefix(code.count / 2) + " " + code.suffix(code.count - code.count / 2))
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .frame(height: 24, alignment: .leading)
                                .contentTransition(.numericText())
                            LevelBar(fraction: remaining, color: left <= 5 ? .orange : .brand)
                        }
                        .animation(.snappy, value: code)
                    }
                }
                }
}

/// Light: a plain white card. Dark: the deep neutral card. Same layout in both.
private struct HeroStyle {
    let dark: Bool
    var ink: Color { dark ? .white : Color(red: 0.07, green: 0.09, blue: 0.16) }
    var muted: Color { dark ? .white.opacity(0.72) : Color(red: 0.07, green: 0.09, blue: 0.16).opacity(0.58) }
    var tile: Color { dark ? .white.opacity(0.06) : Color.black.opacity(0.035) }
    var tileEdge: Color { dark ? .white.opacity(0.07) : Color.black.opacity(0.04) }
    var track: Color { dark ? .white.opacity(0.15) : Color.brand.opacity(0.14) }
    var bar: Color { dark ? .white : .brand }
    var avatar: Color { dark ? .white.opacity(0.14) : Color.brand.opacity(0.10) }
    var avatarInk: Color { dark ? .white : .brand }
    var secondaryButton: Color { dark ? .white.opacity(0.14) : Color.primary.opacity(0.06) }
}

private struct HeroCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let item: VaultItem
    @Binding var reveal: Bool

    var body: some View {
        let style = HeroStyle(dark: scheme == .dark)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                // Same icon as the list row (website icon, else the letter tile).
                ItemIcon(item: item, size: 52)
                    .shadow(color: .black.opacity(style.dark ? 0.3 : 0.08), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 30, weight: .heavy)).tracking(-0.8).lineLimit(1)
                    Text(verbatim: [item.username, item.host].compactMap { $0 }.joined(separator: " · "))
                        .foregroundStyle(style.muted).lineLimit(1)
                }
            }

            // Tiles share one height: the row sizes to the tallest, each tile fills it. Stacked when the card is narrow
            // (decided in the layout pass, so it's always right for the current width).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { tiles(style) }
                    .frame(minWidth: 0, idealWidth: 440, maxWidth: .infinity)
                VStack(spacing: 10) { tiles(style) }
            }
            .fixedSize(horizontal: false, vertical: true)

        }
        .foregroundStyle(style.ink)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Plain surface, no colour wash.
            (style.dark ? Color.hero : Color.panelStrong)
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(style.dark ? Color.white.opacity(0.08) : Color.panelEdge))
        .shadow(color: .black.opacity(style.dark ? 0.3 : 0.07), radius: style.dark ? 24 : 18, y: style.dark ? 16 : 8)
    }
}

private struct Tile<Content: View>: View {
    let style: HeroStyle
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) { content }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(style.tile, in: .rect(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(style.tileEdge))
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

struct DetailRow<Value: View>: View {
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
    @Environment(\.colorScheme) private var scheme

    /// One calm style for every initial (no per-name rainbow): a soft tail-sky tile with the letter in the brand ink.
    var body: some View {
        let dark = scheme == .dark
        Text(name.prefix(1).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(dark ? Color.brandFill : Color.onBrandFill)
            .frame(width: size, height: size)
            .background(Color.brandFill.opacity(dark ? 0.16 : 0.28), in: .rect(cornerRadius: size * 0.29, style: .continuous))
            .accessibilityHidden(true) // decorative: the name is read next to it
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
            PasswordField(title: "Master password", text: $password, onSubmit: submit)
                .frame(width: 260)
            if let error = model.errorMessage {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
            }
            Button("Unlock") { submit() }
                .buttonStyle(.appPrimary)
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

/// One look for every header control: the same fill, hairline edge and soft shadow.
struct HeaderChrome: ViewModifier {
    enum Shape { case capsule, circle }
    let shape: Shape
    var hovering = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let fill = dark ? Color.white.opacity(hovering ? 0.14 : 0.10) : Color.white.opacity(hovering ? 1 : 0.88)
        let edge = dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        Group {
            switch shape {
            case .capsule: content.background(fill, in: .capsule).overlay(Capsule().strokeBorder(edge, lineWidth: 0.5))
            case .circle: content.background(fill, in: .circle).overlay(Circle().strokeBorder(edge, lineWidth: 0.5))
            }
        }
    }
}

/// Icon buttons inside the header pill: a soft highlight on hover and press.
struct HeaderIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(pressed: configuration.isPressed) { configuration.label }
    }

    private struct HoverHighlight<Label: View>: View {
        let pressed: Bool
        @ViewBuilder let label: Label
        @State private var hovering = false
        var body: some View {
            label
                .background(Color.primary.opacity(pressed ? 0.12 : hovering ? 0.07 : 0), in: .capsule)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
