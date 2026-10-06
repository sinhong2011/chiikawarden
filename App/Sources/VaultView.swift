import AppKit
import TriCrypto
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

    /// Sidebar selection: the tail sky deepened so white text reads on it (light: like the primary buttons).
    static let sidebarSelection = adaptive(light: Color(red: 0x2E / 255, green: 0x8F / 255, blue: 0xD3 / 255),
                                           dark: Color(red: 0x2C / 255, green: 0x6E / 255, blue: 0x9E / 255))

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
    /// A full-page section's left inset inside the pane: the same as the item list panel's, so its left edge sits under
    /// the header's search field. On the right, content runs to the pane's edge, as far from the window's edge as the
    /// sidebar is on the left.
    static let pageInset: CGFloat = 6
    var initialSelection: VaultItem.ID?
    /// The section to open on (snapshots).
    var initialSection: SidebarSelection?
    /// Narrow windows: the strip's starting pane (snapshots and previews).
    var initialDepth = 1
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var section: SidebarSelection = .section(.all)
    @AppStorage("itemSort") private var sortRaw = ItemSort.title.rawValue
    @AppStorage("itemSortAscending") private var ascending = true
    /// Window width, to adapt from three columns down to a single phone-width column.
    @State private var width: CGFloat = 1120
    @State private var columns = NavigationSplitViewVisibility.all
    /// Narrow windows: which pane of the strip is in view (0 sidebar, 1 list or page, 2 detail).
    @State private var depth = 1


    /// Below this width the sidebar, list and detail become one sliding strip (Reeder-style).
    /// The item list's width beside the details (wide windows).
    static let listWidth: CGFloat = 330
    /// Below this the panes slide one at a time; it grows with the list so the details keep their room.
    private var compact: Bool { width < 900 + (Self.listWidth - 300) }

    /// Search and + span exactly the list panel below. On wide windows the header's slot starts at the list column
    /// (listWidth, its panel 6 pt in), so: 6 pt in, and the panel's width less + and its gap. Narrow layouts have the
    /// window buttons above the list, so they keep a plain width.
    private var searchLayout: (width: CGFloat, inset: CGFloat) {
        guard !compact else { return (width < 560 ? 150 : 228, 0) }
        return (Self.listWidth - 12 - 40, 6)
    }
    /// The window's footer (Sync, Lock) on its own strip under `content`, so it never sits over a panel; its right edge
    /// under the header's right end (an item's actions, or a page's edge).
    private func withFooter(_ content: some View) -> some View {
        VStack(spacing: 8) {
            content.frame(maxHeight: .infinity)
            if vaultOpen {
                AppFooter()
            }
        }
    }

    /// An item's detail is showing, with its actions in the header.
    private var detailHasActions: Bool { isItemSection && model.selectedItem != nil && (!compact || depth == 2) }
    private var isItemSection: Bool { ![.codes, .generator, .sends, .watchtower].contains(section) }
    private var maxDepth: Int { isItemSection ? (model.selectedItem == nil ? 1 : 2) : 1 }

    private var sort: ItemSort { ItemSort(rawValue: sortRaw) ?? .title }

    private var filtered: [VaultItem] {
        let matching = model.vaultItems
            .filter(section.includes)
            .filter { item in
                query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
                    || (item.username?.localizedCaseInsensitiveContains(query) ?? false)
                    || (item.host?.localizedCaseInsensitiveContains(query) ?? false)
            }
        return ItemSort.sorted(matching, by: sort, ascending: ascending)
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
        if let id = model.focusedAccountID ?? { if case .account(let id) = section { id } else { nil } }(),
           !model.isUnlocked(id), let account = model.accounts.first(where: { $0.id == id }) {
            AccountUnlockPane(account: account) // the account in focus is locked: unlock it right here
        } else {
            ItemColumn(items: filtered, isTrash: section == .section(.trash), selection: Binding(get: { model.selectedID }, set: { id in
                model.selectedID = id
                if compact, id != nil { depth = 2 } // tapping an item slides to it
            }), query: $query, sort: $sortRaw, ascending: $ascending)

        }
    }

    @ViewBuilder private var detailPane: some View {
        if let item = model.selectedItem {
            ItemDetail(item: item)
                .id(item.id)
                .transition(.opacity.combined(with: .offset(y: 8)))
        } else {
            ContentUnavailableView {
                Label("No Item Selected", systemImage: "key.viewfinder").modifier(Floating())
            }
        }
    }

    /// False while the lock layer lies over the vault: the header's controls are kept in place but out of sight.
    private var vaultOpen: Bool { model.phase.id == AppModel.Phase.vault.id }

    private var content: some View {
        @Bindable var model = model
        return NavigationSplitView(columnVisibility: $columns) {
            Sidebar(section: $section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                // Narrow windows navigate with the strip's own back button; one sidebar control is enough. None under
                // the lock layer (the toolbar itself stays, so the window keeps its controls and the layout doesn't move).
                .toolbar(removing: compact || !vaultOpen ? .sidebarToggle : nil)
        } detail: {
            Group {
                if compact {
                    withFooter(PaneStrip(panes: compactPanes, depth: $depth, maxDepth: maxDepth))
                } else if isItemSection {
                    HStack(spacing: 8) {
                        listPane.frame(width: Self.listWidth) // full height: the footer stays under the right column
                        withFooter(detailPane.frame(maxWidth: .infinity, maxHeight: .infinity))
                    }
                } else {
                    withFooter(sectionPane)
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
                            let layout = searchLayout
                            PaletteTrigger()
                                .frame(width: layout.width)
                                .padding(.leading, layout.inset)

                            NewItemButton()
                        }
                    }
                    // Under the lock layer: present (so the header keeps its height and nothing moves on unlock)
                    // but invisible and inert.
                    .opacity(vaultOpen ? 1 : 0)
                    .disabled(!vaultOpen) // shortcuts too
                    .accessibilityHidden(!vaultOpen)
                }
                .sharedBackgroundVisibility(.hidden)
                // A copied secret's countdown: top right, its edge on the page's (an item shows it beside its actions).
                if model.clipboardClearsAt != nil, vaultOpen, !detailHasActions {
                    ToolbarSpacer(.flexible)
                    ToolbarItem { ClipboardCountdown() }
                        .sharedBackgroundVisibility(.hidden)
                }
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
        .sheet(item: $model.repromptRequest) { request in RepromptSheet(request: request) }
        .sheet(item: $model.signInPrompt) { prompt in SignInApprovalSheet(prompt: prompt) }
        .sheet(isPresented: Binding(get: { model.eventLogFor != nil }, set: { if !$0 { model.eventLogFor = nil } })) {
            if let id = model.eventLogFor { EventLogSheet(organizationId: id) }
        }
        .sheet(item: $model.organizationSheet) { sheet in
            switch sheet {
            case .share(let ids): MoveToOrganizationSheet(itemIDs: ids)
            case .collections(let id): CollectionsSheet(itemID: id)
            }
        }
        .sheet(item: $model.transfer) { transfer in
            switch transfer {
            case .export(let accountId): ExportSheet(initialAccount: accountId)
            case .importFile(let url): ImportSheet(initialFile: url)
            }
        }
        // Drop an export file (from any supported app) on the window to import it.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, ["csv", "json", "xml", "1pux"].contains(url.pathExtension.lowercased()), !model.sessions.isEmpty else { return false }
            model.beginImport(url)
            return true
        }
        .quickLookPreview($model.previewURL)
        .onChange(of: model.previewURL) { old, _ in
            if let old { AttachmentFiles.remove(old) } // decrypted copy only lives while previewed
        }
        .sheet(isPresented: $model.promptingNewFolder) { NewFolderSheet() }
        .overlay(alignment: .bottom) { ToastView() }
        .onAppear {
            if let initialSection { section = initialSection }
            selectFirst()
        }
        // Under the lock layer the vault starts empty; pick an item once unlocking fills it.
        .onChange(of: model.items.isEmpty) { _, empty in if !empty { selectFirst() } }
    }

    private func selectFirst() {
        if model.selectedID == nil { model.selectedID = initialSelection ?? model.items.first(where: \.favorite)?.id ?? model.items.first?.id }
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
        case .account(let id): !item.isDeleted && !item.isArchived && item.accountId == id
        case .section(let s): s.includes(item)
        case .folder(let path): !item.isDeleted && !item.isArchived && (item.folderName == path || item.folderName?.hasPrefix(path + "/") == true)
        case .organization(let id): !item.isDeleted && !item.isArchived && item.organizationId == id
        case .collection(let id): !item.isDeleted && !item.isArchived && item.collectionIds.contains(id)
        }
    }
}

enum VaultSection: Hashable, CaseIterable {
    case all, favorites, logins, passkeys, cards, identities, notes, sshKeys, archive, trash

    /// Shown nested under All Items: narrower views of the same items.
    static let underAll: [VaultSection] = [.favorites, .logins, .passkeys, .cards, .identities, .notes, .sshKeys]

    var title: LocalizedStringKey {
        switch self {
        case .all: "All Items"; case .favorites: "Favorites"; case .logins: "Logins"; case .passkeys: "Passkeys"
        case .sshKeys: "SSH Keys"; case .cards: "Cards"; case .identities: "Identities"; case .notes: "Secure Notes"
        case .archive: "Archive"; case .trash: "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"; case .favorites: "star"; case .logins: "key"; case .passkeys: "person.badge.key"
        case .sshKeys: "terminal"; case .cards: "creditcard"; case .identities: "person.crop.rectangle"; case .notes: "note.text"
        case .archive: "archivebox"; case .trash: "trash"
        }
    }

    func includes(_ item: VaultItem) -> Bool {
        if self == .trash { return item.isDeleted }
        if item.isDeleted { return false }
        // Archived items live only in Archive (as in Bitwarden): out of every other list.
        if self == .archive { return item.isArchived }
        if item.isArchived { return false }
        switch self {
        case .trash, .archive: return true
        case .all: return true
        case .favorites: return item.favorite
        case .logins: return item.kind == .login
        case .passkeys: return item.hasPasskey
        case .sshKeys: return item.kind == .sshKey
        case .cards: return item.kind == .card
        case .identities: return item.kind == .identity
        case .notes: return item.kind == .note
        }
    }
}

/// Native macOS sidebar (system source-list style, adapts to the OS look).
private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var section: SidebarSelection

    @AppStorage("sidebarTypesExpanded") private var typesExpanded = true
    @AppStorage("sidebarFoldersExpanded") private var foldersExpanded = true

    private func count(_ selection: SidebarSelection) -> Int { model.vaultItems.filter(selection.includes).count }

    private func row(_ s: VaultSection) -> some View {
        SidebarLabel(s.title, symbol: s.symbol, tag: .section(s), count: count(.section(s)))
            .tag(SidebarSelection.section(s))
    }

    var body: some View {
        List(selection: Binding(get: { section }, set: { if let s = $0 { section = s } })) {
            Section("Vault") {
                // All Items, with its narrower views folded under it: favorites, each type, then the folders.
                DisclosureGroup(isExpanded: $typesExpanded) {
                    ForEach(VaultSection.underAll, id: \.self) { row($0) }
                    if !model.folders.isEmpty {
                        DisclosureGroup(isExpanded: $foldersExpanded) {
                            ForEach(FolderNode.tree(model.folders)) { node in
                                FolderRow(node: node, count: count)
                            }
                        } label: {
                            SidebarLabel("Folders", symbol: "folder")
                        }
                    }
                } label: {
                    row(.all)
                }
                row(.archive)
                row(.trash)
            }
            // Things to do with the vault, rather than kinds of items in it.
            Section("Tools") {
                SidebarLabel("Send", symbol: "paperplane", tag: .sends, count: model.sends.count)
                    .tag(SidebarSelection.sends)
                SidebarLabel("One-Time Codes", symbol: "clock.badge.checkmark", tag: .codes,
                             count: model.vaultItems.filter { !$0.isDeleted && !$0.isArchived && $0.totp != nil }.count)
                    .tag(SidebarSelection.codes)
                SidebarLabel("Generator", symbol: "dice", tag: .generator)
                    .tag(SidebarSelection.generator)
                SidebarLabel("Watchtower", symbol: "checkmark.shield", tag: .watchtower, count: model.watchtowerIssueCount)
                    .tag(SidebarSelection.watchtower)
            }
            ForEach(model.visibleOrganizations) { org in
                Section(org.name) {
                    SidebarLabel("All Items", symbol: "building.2", tag: .organization(org.id), count: count(.organization(org.id)))
                        .tag(SidebarSelection.organization(org.id))
                        .contextMenu {
                            Button("Event Log…", systemImage: "list.bullet.rectangle") { model.eventLogFor = org.id }
                                .labelStyle(.titleAndIcon)
                            Button("Leave Organization…", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                model.leaveOrganization(org.id)
                            }
                            .labelStyle(.titleAndIcon)
                        }
                    ForEach(org.children) { collection in
                        SidebarLabel(verbatim: collection.name, symbol: "rectangle.stack", tag: .collection(collection.id),
                                     count: count(.collection(collection.id)))
                            .tag(SidebarSelection.collection(collection.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarCurrent, section)
        // Switching accounts or vaults: sections and counts move rather than jump.
        .animation(.snappy(duration: 0.3), value: model.focusedAccountID)
        .animation(.snappy(duration: 0.3), value: model.vaultFilter)
        .listItemTint(.monochrome) // icons in the text's own colour, not the brand blue
        // Selection: a calm sky (deep in dark mode) that white text reads well on, not the bright accent.
        .tint(Color.sidebarSelection)
        .safeAreaInset(edge: .bottom) { SidebarAccountCard().padding(10) }
        // The vault switcher above the list, as wide as the rows' selection.
        .safeAreaInset(edge: .top, spacing: 4) {
            if !model.visibleOrganizations.isEmpty {
                VaultSwitcher().padding(.horizontal, 10).padding(.top, 4)
            }
        }
    }
}

/// Who's signed in, where, and how fresh the vault is — with sync and lock at hand. A click opens the account
/// switcher: every account (or all of them together), the locked ones a click from unlocking, and the rest.
private struct SidebarAccountCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    @State private var switching = false

    /// The account the card stands for: the one in focus, the only one, or none (several together).
    private var account: (index: Int, account: SavedAccount)? {
        let id = model.focusedAccountID ?? (model.accounts.count == 1 ? model.accounts.first?.id : nil)
        return model.accounts.enumerated().first { $0.element.id == id }.map { ($0.offset, $0.element) }
    }

    private var title: String {
        if let account { return account.account.email }
        let open = model.sessions.count
        return open == 0 ? String(localized: "Vault") : String(localized: "All accounts")
    }

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 10) {
            Button { switching.toggle() } label: {
                HStack(spacing: 10) {
                    if let account {
                        AccountAvatar(email: account.account.email, index: account.index, size: 30)
                    } else {
                        StackedAvatars(accounts: model.accounts)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: title).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                            .contentTransition(.opacity)
                        SyncStatusText().font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    // The switcher's pop-up mark, centred on the card's right end.
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Accounts"))
            .accessibilityValue(Text(verbatim: title))
            .popover(isPresented: $switching, arrowEdge: .top) {
                AccountSwitcher(close: { switching = false })
            }
        }
        .padding(.leading, 8).padding(.trailing, 8).padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(dark ? Color.white.opacity(hovering || switching ? 0.09 : 0.06) : Color.white.opacity(hovering || switching ? 0.75 : 0.55))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(dark ? 0.08 : 0.05)))
        }
        .onHover { h in withAnimation(.snappy(duration: 0.15)) { hovering = h } }
        .animation(.snappy(duration: 0.25), value: model.focusedAccountID)
    }

}

/// The window's footer, under the panels: Sync Now and Lock at the right end, in the header's pill style.
private struct AppFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                SyncFooterButton { Task { try? await model.refresh() } }
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 14).padding(.horizontal, 2)
                Button { model.lock(animated: true) } label: {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(.rect)
                }
                .buttonStyle(HeaderIconStyle())
                .help(Text("Lock Vault (⇧⌘L)"))
                .accessibilityLabel(Text("Lock Vault"))
            }
            .padding(.horizontal, 3)
            .frame(height: 30)
            .modifier(HeaderChrome(shape: .capsule))
        }
    }
}

/// The footer's Sync Now: spins while syncing, then shows a tick for a moment when a sync you asked for is done.
private struct SyncFooterButton: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void
    @State private var asked = false
    @State private var done = false

    var body: some View {
        Button {
            asked = true
            action()
        } label: {
            Image(systemName: done ? "checkmark" : "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: done ? .semibold : .medium))
                .foregroundStyle(.secondary)
                .symbolEffect(.rotate, isActive: model.isSyncing)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(HeaderIconStyle())
        .disabled(model.isSyncing)
        .help(Text("Sync Now"))
        .accessibilityLabel(Text("Sync Now"))
        .onChange(of: model.isSyncing) { was, now in
            guard was, !now, asked else { return }
            asked = false
            guard model.lastSynced.map({ Date.now.timeIntervalSince($0) < 5 }) ?? false else { return } // it failed
            done = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                done = false
            }
        }
    }
}

/// An account's monogram with its colour dot.
private struct AccountAvatar: View {
    let email: String
    let index: Int
    var size: CGFloat = 28
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Monogram(name: email, size: size)
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(AccountColor.color(index))
                    .frame(width: size * 0.32, height: size * 0.32)
                    .overlay(Circle().strokeBorder(scheme == .dark ? Color.black.opacity(0.6) : .white, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
    }
}

/// Several accounts at once: their monograms fanned out.
private struct StackedAvatars: View {
    let accounts: [SavedAccount]

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(accounts.prefix(3).enumerated().reversed()), id: \.element.id) { index, account in
                Monogram(name: account.email, size: 24)
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5).padding(-0.75))
                    .offset(x: CGFloat(index) * 8, y: CGFloat(index) * -3)
            }
        }
        .frame(width: 30 + CGFloat(min(accounts.count, 3) - 1) * 4, height: 30, alignment: .leading)
    }
}

/// The account switcher: all accounts together or one at a time (a locked one unlocks in the list), then the
/// account actions.
struct AccountSwitcher: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.accounts.count > 1 {
                row(selected: model.focusedAccountID == nil, action: { focus(nil) }) {
                    StackedAvatars(accounts: model.accounts)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("All accounts").font(.system(size: 13, weight: .semibold))
                        Text("\(model.sessions.count) of \(model.accounts.count) unlocked")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.vertical, 4).padding(.horizontal, 8)
            }
            ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                let open = model.isUnlocked(account.id)
                row(selected: model.focusedAccountID == account.id || model.accounts.count == 1, action: { focus(account.id) }) {
                    AccountAvatar(email: account.email, index: index, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: account.email).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 4) {
                            if open {
                                Text(verbatim: account.serverSummary)
                                Text(verbatim: "·")
                                Text("^[\(model.items.filter { $0.accountId == account.id && !$0.isDeleted }.count) item](inflect: true)")
                            } else {
                                Image(systemName: "lock.fill").font(.system(size: 9))
                                Text("Locked · \(account.serverSummary)")
                            }
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .contextMenu {
                    Group {
                        if open { Button("Lock", systemImage: "lock") { model.lock(account.id) } }
                        Button("Log Out…", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            close(); model.confirmLogOut(account.id)
                        }
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
            Divider().padding(.vertical, 4).padding(.horizontal, 8)
            action("Add Account…", "person.badge.plus") { model.beginAddAccount() }
            action("Sync Now", "arrow.triangle.2.circlepath") { Task { try? await model.refresh() } }
            action("Import…", "square.and.arrow.down", keys: "⇧⌘I") { model.beginImport() }
            action("Export Vault…", "square.and.arrow.up", keys: "⇧⌘E") { model.beginExport() }
            action("Settings…", "gearshape", keys: "⌘,") { model.showSettings() }
            Divider().padding(.vertical, 4).padding(.horizontal, 8)
            action("Lock Vault", "lock", keys: "⇧⌘L") { model.lock(animated: true) }
            action("Log Out…", "rectangle.portrait.and.arrow.right", destructive: true) {
                model.confirmLogOut(model.focusedAccountID ?? (model.sessions.count == 1 ? model.sessions[0].account.id : nil))
            }
        }
        .padding(6)
        .frame(width: 300)
    }

    private func focus(_ id: String?) {
        withAnimation(.snappy(duration: 0.3)) {
            model.accountFocus = id
            model.vaultFilter = .all // an organization of another account wouldn't be there
        }
        close()
    }

    private func row<Content: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        SwitcherRow(selected: selected, action: action, content: content())
    }

    private func action(_ title: LocalizedStringKey, _ symbol: String, keys: String? = nil, destructive: Bool = false,
                        run: @escaping () -> Void) -> some View {
        SwitcherAction(title: title, symbol: symbol, keys: keys, destructive: destructive) { close(); run() }
    }
}

private struct SwitcherRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                content
                Spacer(minLength: 6)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.primary.opacity(hovering ? 0.07 : selected ? 0.04 : 0), in: .rect(cornerRadius: 9, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy(duration: 0.12)) { hovering = h } }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SwitcherAction: View {
    let title: LocalizedStringKey
    let symbol: String
    /// The menu-bar shortcut, drawn on the right the way a menu shows it.
    var keys: String?
    var destructive = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(title, systemImage: symbol)
                    .foregroundStyle(destructive ? Color.red : .primary)
                Spacer(minLength: 8)
                if let keys {
                    Text(verbatim: keys).foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8).frame(height: 28)
            .background(Color.primary.opacity(hovering ? 0.07 : 0), in: .rect(cornerRadius: 7, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy(duration: 0.12)) { hovering = h } }
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
        let label = SidebarLabel(verbatim: node.name, symbol: node.folderIds.isEmpty ? "folder.badge.questionmark" : "folder",
                                 tag: .folder(node.path), count: count(.folder(node.path)))
            .tag(SidebarSelection.folder(node.path))
            .listRowBackground(targeted ? Color.brand.opacity(0.18).clipShape(.rect(cornerRadius: 6)) : nil)
            .dropDestination(for: String.self) { ids, _ in
                guard !node.folderIds.isEmpty else { return false }
                Task { await model.move(itemIDs: ids, toFolderIn: node.folderIds) }
                return true
            } isTargeted: { targeted = $0 }
            .contextMenu {
                if !node.folderIds.isEmpty {
                    Button("Delete Folder…", systemImage: "folder.badge.minus", role: .destructive) {
                        model.confirmDeleteFolder(name: node.name, ids: node.folderIds)
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
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
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Secure Note", systemImage: "note.text") { model.editing = EditRequest(mode: .create(.secureNote)) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Card", systemImage: "creditcard") { model.editing = EditRequest(mode: .create(.card)) }
                Button("New Identity", systemImage: "person.crop.rectangle") { model.editing = EditRequest(mode: .create(.identity)) }
                Button("New SSH Key", systemImage: "terminal") { model.editing = EditRequest(mode: .create(.sshKey)) }
                Divider()
                Button("New Send", systemImage: "paperplane") {
                    model.requestedSection = .sends
                    model.composingSend = true
                }
                Button("New Folder…", systemImage: "folder.badge.plus") { model.promptingNewFolder = true }
                    .keyboardShortcut("n", modifiers: [.command, .option])
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
                    .padding(.leading, VaultView.pageInset)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
            }
            .modifier(SideOverflowClip())
            .thinScroller()
        }
    }
}

// MARK: Item column

/// How the item list is ordered, and the section headers that go with it.
enum ItemSort: String, CaseIterable, Identifiable {
    case title, edited, created
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self { case .title: "Title"; case .edited: "Date Edited"; case .created: "Date Created" }
    }
    var symbol: String {
        switch self { case .title: "textformat"; case .edited: "pencil"; case .created: "calendar" }
    }
    func orderTitle(ascending: Bool) -> LocalizedStringKey {
        switch self {
        case .title: ascending ? "A to Z" : "Z to A"
        case .edited, .created: ascending ? "Oldest First" : "Newest First"
        }
    }

    /// The index letter for a title: A–Z, with Chinese and Japanese romanised (銀行 → Y) and everything else "#".
    static func letter(_ name: String) -> String {
        let latin = name.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? name
        guard let first = latin.trimmingCharacters(in: .whitespacesAndNewlines).first.map({ String($0).uppercased() }),
              first.count == 1, ("A"..."Z").contains(first) else { return "#" }
        return first
    }

    private func date(_ item: VaultItem) -> Date? { self == .created ? item.created : item.revised }

    static func sorted(_ items: [VaultItem], by sort: ItemSort, ascending: Bool) -> [VaultItem] {
        switch sort {
        case .title:
            // Letters A–Z, then # (numbers and symbols), then by name within a letter.
            let keyed = items.map { (item: $0, letter: letter($0.name)) }
            let ordered = keyed.sorted { a, b in
                if a.letter != b.letter {
                    if a.letter == "#" || b.letter == "#" { return b.letter == "#" }
                    return a.letter < b.letter
                }
                return a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
            }.map(\.item)
            return ascending ? ordered : ordered.reversed()
        case .edited, .created:
            // Items without a date go last either way.
            let dated = items.filter { sort.date($0) != nil }.sorted { sort.date($0)! < sort.date($1)! }
            return (ascending ? dated : dated.reversed()) + items.filter { sort.date($0) == nil }
        }
    }

    /// Consecutive runs of the (already sorted) items under one header each.
    static func sections(_ items: [VaultItem], by sort: ItemSort) -> [(title: String, items: [VaultItem])] {
        let month = Date.FormatStyle().month(.wide).year()
        var out: [(title: String, items: [VaultItem])] = []
        for item in items {
            let title: String
            switch sort {
            case .title: title = letter(item.name)
            case .edited, .created: title = sort.date(item).map { $0.formatted(month) } ?? String(localized: "No Date")
            }
            if out.last?.title == title { out[out.count - 1].items.append(item) } else { out.append((title, [item])) }
        }
        return out
    }
}

/// A pinned list header ("A", "October 2026"): plain text on the list's surface, like Contacts and 1Password.
private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 20)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct ItemColumn: View {
    let items: [VaultItem]
    /// The Trash: a note on when its items go for good.
    var isTrash = false
    @Binding var selection: VaultItem.ID?
    @Binding var query: String
    @Binding var sort: String
    @Binding var ascending: Bool

    @Environment(AppModel.self) private var model

    private func picked(_ item: VaultItem) -> Bool {
        model.multiSelection.isEmpty ? item.id == selection : model.multiSelection.contains(item.id)
    }

    /// A click: plain selects one; ⌘ adds or removes; ⇧ extends from the selected item in list order.
    private func click(_ item: VaultItem, ordered: [VaultItem]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            var picked = model.multiSelection.isEmpty ? Set(selection.map { [$0] } ?? []) : model.multiSelection
            if picked.contains(item.id) { picked.remove(item.id) } else { picked.insert(item.id) }
            withAnimation(.snappy(duration: 0.2)) { model.multiSelection = picked.count > 1 ? picked : [] }
            if picked.count <= 1 { selection = picked.first ?? item.id }
        } else if flags.contains(.shift), let anchor = selection, let a = ordered.firstIndex(where: { $0.id == anchor }),
                  let b = ordered.firstIndex(where: { $0.id == item.id }), a != b {
            withAnimation(.snappy(duration: 0.2)) { model.multiSelection = Set(ordered[min(a, b)...max(a, b)].map(\.id)) }
        } else {
            if !model.multiSelection.isEmpty { withAnimation(.snappy(duration: 0.2)) { model.multiSelection = [] } }
            selection = item.id
        }
    }

    private func step(_ delta: Int, _ proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : items.count)
        let next = items[min(max(current + delta, 0), items.count - 1)].id
        selection = next
        proxy.scrollTo(next)
    }

    var body: some View {
        let order = ItemSort(rawValue: sort) ?? .title
        VStack(spacing: 10) {
            // How many, and how they're ordered (the sidebar filters; this only sorts).
            HStack(spacing: 6) {
                Text("\(items.count) items").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(ItemSort.allCases) { Label($0.title, systemImage: $0.symbol).tag($0.rawValue) }
                    }
                    .pickerStyle(.inline)
                    Picker("Order", selection: $ascending) {
                        Text(order.orderTitle(ascending: true)).tag(true)
                        Text(order.orderTitle(ascending: false)).tag(false)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .modifier(HeaderChrome(shape: .circle))
                        .contentShape(.circle)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Text("Sort"))
                .accessibilityLabel(Text("Sort"))
            }
            .padding(.leading, 6) // the sort button lines up with the list's edge (and + above it)

            if isTrash, !items.isEmpty { TrashNotice(items: items) }

            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    // A–Z (then #) by title, or by month by date.
                    ForEach(ItemSort.sections(items, by: order), id: \.title) { group in
                        Section {
                            ForEach(group.items) { item in
                                ItemRow(item: item, isSelected: picked(item), highlight: query)
                                    .modifier(ArrivalPop(arrived: model.arrivedID == item.id))
                                    .onTapGesture { click(item, ordered: ItemSort.sections(items, by: order).flatMap(\.items)) }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(item.id == selection ? [.isButton, .isSelected] : .isButton)
                                    .accessibilityAction { selection = item.id }
                                    .draggable(item.id) { ItemRow(item: item, isSelected: true).frame(width: 260) }
                                    .contextMenu { ItemContextMenu(item: item) }
                                    // Trashed, archived or deleted: the row slips out; restored ones fade back in.
                                    .transition(.asymmetric(insertion: .opacity,
                                                            removal: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .move(edge: .leading))))
                            }
                        } header: {
                            SectionHeader(title: group.title)
                        }
                    }
                }
                .padding(6)
            }
            // ↑/↓ move the selection; the search field hands focus here with ↓ too.
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { step(1, proxy); return .handled }
            .onKeyPress(.upArrow) { step(-1, proxy); return .handled }
            .onKeyPress(.escape) {
                guard !model.multiSelection.isEmpty else { return .ignored }
                withAnimation(.snappy(duration: 0.2)) { model.multiSelection = [] }
                return .handled
            }
            .onKeyPress(characters: ["a"], phases: .down) { press in
                guard press.modifiers.contains(.command), items.count > 1 else { return .ignored }
                withAnimation(.snappy(duration: 0.2)) { model.multiSelection = Set(items.map(\.id)) }
                return .handled
            }
            }
            .thinScroller() // the app's slim scroller: on hover and while scrolling
            .background(Color.panel, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "No Items" : "No Results", systemImage: query.isEmpty ? "tray" : "magnifyingglass")
                            .modifier(Floating())
                    }
                }
            }
            .overlay(alignment: .bottom) {
                let picked = items.filter { model.multiSelection.contains($0.id) }
                if picked.count > 1 {
                    SelectionBar(items: picked)
                        .padding(10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: model.multiSelection.count > 1)
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
                // Marks in one row under the name, so the name keeps the full width.
                let issue = item.passwordIssue(breaches: model.breachCounts)
                let purge = model.purgeDate(item)
                if issue != nil || item.favorite || item.hasTOTP || purge != nil {
                    HStack(spacing: 6) {
                        if let purge { PurgeChip(date: purge) }
                        if let issue {
                            HStack(spacing: 3) {
                                Image(systemName: issue.rowSymbol).font(.system(size: 9, weight: .bold))
                                Text(issue.shortLabel).font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(issue.tint)
                            .padding(.horizontal, 6).frame(height: 17)
                            .background(issue.tint.opacity(0.14), in: .capsule)
                            .help(Text(issue.rowLabel))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(issue.rowLabel))
                        }
                        if item.favorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.yellow)
                                .accessibilityLabel(Text("Favorite"))
                        }
                        if item.hasTOTP {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.system(size: 11, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                                .help(Text("Has a one-time code"))
                                .accessibilityLabel(Text("Has a one-time code"))
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            Spacer(minLength: 0)
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
    /// The cards' inset from the list (on the right they run to the pane's edge, like the header and footer).
    static let detailInset: CGFloat = 18
    @Environment(\.showsDetailToolbar) private var showsToolbar
    @Environment(AppModel.self) private var model
    let item: VaultItem
    @State private var revealToggle = false
    @State private var starBurst = 0
    @State private var confirmDelete = false
    @State private var dropping = false
    /// Revealed while toggled on, or while ⌥ is held.
    private var reveal: Binding<Bool> {
        // Holding ⌥ peeks, except on items that ask for the master password first.
        Binding(get: { revealToggle || (model.optionHeld && model.isRepromptPassed(item)) }, set: { revealToggle = $0 })
    }

    var body: some View {
        ScrollView {
            StaggeredStack(spacing: 18) {
                if item.isDeleted {
                    Group {
                        if let purge = model.purgeDate(item) {
                            Label("In Trash until \(purge.formatted(date: .abbreviated, time: .omitted)), when Bitwarden deletes it for good. Restore it to use it again.",
                                  systemImage: "trash")
                        } else {
                            Label("In Trash. Restore it to use it again, or delete it forever.", systemImage: "trash")
                        }
                    }
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HeroCard(item: item, reveal: reveal)

                if !item.fields.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(item.fields.enumerated()), id: \.element.id) { index, field in
                            FieldLine(item: item, field: field, reveal: reveal.wrappedValue)
                                .overlay(alignment: .top) { if index > 0 { Divider().opacity(0.6).padding(.leading, 16) } }
                        }
                    }
                    .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))
                }

                VStack(spacing: 0) {
                    if let address = item.uri ?? item.host,
                       let url = URL(string: address.contains("://") ? address : "https://" + address) {
                        DetailRow(symbol: "globe", title: "Website") {
                            Button { NSWorkspace.shared.open(url) } label: {
                                HStack(spacing: 5) {
                                    Text(verbatim: address).lineLimit(1).truncationMode(.middle)
                                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(.primary)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .help(Text("Open in your browser"))
                            .contextMenu {
                                Button("Copy", systemImage: "doc.on.doc") { model.copyPlain(address) }
                            }
                        }
                    }
                    if item.organizationId == nil {
                        DetailRow(symbol: "person", title: "Owner") {
                            Text(verbatim: model.accounts.first { $0.id == item.accountId }?.email ?? String(localized: "Me"))
                                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    if let orgId = item.organizationId, let org = model.organizations.first(where: { $0.id == orgId }) {
                        DetailRow(symbol: "building.2", title: "Organization") {
                            let names = org.children.filter { item.collectionIds.contains($0.id) }.map(\.name)
                            Button { model.organizationSheet = .collections(item.id) } label: {
                                HStack(spacing: 5) {
                                    Text(verbatim: ([org.name] + names).joined(separator: " › ")).lineLimit(1).truncationMode(.middle)
                                    Image(systemName: "pencil").font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(.secondary).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .help(Text("Change collections"))
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
                            .help(Text("Commands that make git sign commits with this key through the Triwarden SSH agent"))
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
                                Text("Stored with a key type Triwarden can't use").foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let expiry = item.cardExpiry, expiry < WatchtowerReport.expiryHorizon, let text = item.cardExpiryText {
                        DetailRow(symbol: "creditcard", title: "Card") {
                            HStack(spacing: 7) {
                                Circle().fill(item.isCardExpired ? Color.red : Color.orange).frame(width: 7, height: 7)
                                Text(verbatim: text)
                            }
                        }
                    }
                    if item.password != nil {
                        DetailRow(symbol: "checkmark.shield", title: "Watchtower") {
                            HStack(spacing: 10) {
                                HStack(spacing: 7) {
                                    Circle().fill(health.tint).frame(width: 7, height: 7)
                                    Text(health.text)
                                }
                                if let issue = item.passwordIssue(breaches: model.breachCounts), issue != .insecure,
                                   let host = item.host, !host.isEmpty, !item.isDeleted {
                                    ChangeOnSiteButton(host: host)
                                }
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

                // When it was made and changed, and the passwords it had before.
                if item.revised != nil || item.created != nil || !item.passwordHistory.isEmpty {
                    ItemHistoryCard(item: item)
                }
            }
            .padding(.leading, Self.detailInset)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .modifier(SideOverflowClip())
        .thinScroller()
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
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    }
                    .padding(10)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: dropping)
        .toolbar {
            // Item actions sit in the header, top right (Liquid layout) — only while this detail is in view, and not
            // under the lock layer.
            if showsToolbar, model.phase.id == AppModel.Phase.vault.id {
                ToolbarSpacer(.flexible)
                // Inset by the detail's own side padding, so the pill's edge lines up with the cards below.
                ToolbarItem {
                    HStack(spacing: 10) {
                        ClipboardCountdown()
                        actions
                    }
                }
                    .sharedBackgroundVisibility(.hidden)
            }
        }
        .confirmationDialog("Delete “\(item.name)” forever?", isPresented: $confirmDelete) {
            Button("Delete Forever", role: .destructive) { Task { await model.deleteForever(item) } }
        } message: {
            Text("This can't be undone.")
        }
    }

    /// What Watchtower says about this password: the same checks as the list's mark.
    private var health: (text: LocalizedStringKey, tint: Color) {
        guard item.password != nil else { return ("", .secondary) }
        switch item.passwordIssue(breaches: model.breachCounts) {
        case .breached?: return ("Seen in \(model.breachCounts?[item.id] ?? 0) data breaches", .red)
        case .reused?: return ("Reused in \(item.reuseCount + 1) items", .orange)
        case .weak?: return ("Weak password", .orange)
        case .insecure?: return ("Sent unencrypted (http://)", .yellow)
        default: return ("Strong · unique", .green)
        }
    }

    private var actions: some View {
        HStack(spacing: 0) {
            if item.isDeleted {
                toolbarButton("arrow.uturn.backward", help: "Restore", effect: .wiggleBack) { Task { await model.restore(item) } }
                toolbarButton("trash.slash", help: "Delete Forever", effect: .bounce) { confirmDelete = true }
                    .foregroundStyle(.red)
            } else {
                // Reveal, then a divider, whenever the item has anything secret (password, private key, card code…).
                if item.password != nil || item.fields.contains(where: \.secret) {
                    toolbarButton(reveal.wrappedValue ? "eye.slash" : "eye", help: reveal.wrappedValue ? "Hide" : "Reveal (hold ⌥)",
                                  spoken: reveal.wrappedValue ? "Hide" : "Reveal") {
                        if reveal.wrappedValue {
                            withAnimation(.snappy) { reveal.wrappedValue = false }
                        } else {
                            model.guarded(item) { withAnimation(.snappy) { reveal.wrappedValue = true } }
                        }
                    }
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 3)
                }
                toolbarButton(item.isArchived ? "archivebox.fill" : "archivebox", help: item.isArchived ? "Unarchive" : "Archive",
                              spoken: item.isArchived ? "Unarchive" : "Archive", effect: .bounceDown) {
                    Task { await model.setArchived(item, !item.isArchived) }
                }
                toolbarButton(item.favorite ? "star.fill" : "star", help: "Favorite", effect: .bounce) {
                    if !item.favorite { starBurst += 1 }
                    Task { await model.toggleFavorite(item) }
                }
                    .foregroundStyle(item.favorite ? .yellow : .primary)
                    .overlay { Burst(trigger: starBurst) }
                toolbarButton("pencil", help: "Edit (⌘E)", spoken: "Edit", effect: .wiggle) { model.guarded(item) { model.editing = EditRequest(mode: .edit(item)) } }
                toolbarButton("trash", help: "Move to Trash… (⌘⌫)", spoken: "Move to Trash", effect: .bounce) { model.confirmTrash(item) }
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 32)
        .modifier(HeaderChrome(shape: .capsule))
    }

    /// `spoken`: the VoiceOver label when the tooltip carries a shortcut hint, e.g. "Edit" for "Edit (⌘E)".
    private func toolbarButton(_ symbol: String, help: LocalizedStringKey, spoken: LocalizedStringKey? = nil,
                               effect: ToolbarSymbolButton.Effect = .none, action: @escaping () -> Void) -> some View {
        ToolbarSymbolButton(symbol: symbol, effect: effect, action: action)
            .help(Text(help))
            .accessibilityLabel(Text(spoken ?? help))
    }
}

extension HeroCard {
    /// The password and one-time-code tiles.
    @ViewBuilder func tiles(_ style: HeroStyle) -> some View {
                if let password = item.password {
                    Tile(style: style) {
                        passwordArmed = model.copyCount
                        model.copyPassword(item)
                    } content: {
                        let strength = StrengthMeter(password: password).level
                        HStack {
                            CopyCaption(copied: passwordCopied) { Text("Password · click to copy") }
                            Spacer(minLength: 6)
                            Text(strength.1)
                        }
                        .font(.system(size: 12)).foregroundStyle(style.muted)
                        Group {
                            if reveal {
                                DecodingText(password).font(.system(size: 16, weight: .semibold, design: .monospaced)).tracking(0.5)
                            } else {
                                Text(verbatim: String(repeating: "•", count: 12))
                                    .font(.system(size: 20, weight: .semibold, design: .monospaced)).tracking(2)
                            }
                        }
                            .lineLimit(1)
                            .frame(height: 24, alignment: .leading)
                        // Same place and size as the code's countdown bar, so the tiles line up.
                        LevelBar(level: strength.0, color: strength.0 <= 1 ? .red : strength.0 == 2 ? .orange : .green)
                    }
                    .copyTick(armed: $passwordArmed, copied: $passwordCopied)
                    .contextMenu {
                        Button("Copy Password", systemImage: "doc.on.doc") { model.copyPassword(item) }
                        Button("Show in Large Type", systemImage: "textformat.size") { model.showLargeType(item) }
                    }
                }
                if let totp = item.totp {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let code = totp.code(at: context.date)
                        let left = totp.secondsRemaining(at: context.date)
                        let period = Double(totp.period)
                        let remaining = 1 - context.date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
                        Tile(style: style) {
                            codeArmed = model.copyCount
                            model.guarded(item) { model.copy(code, label: String(localized: "Code")) }
                        } content: {
                            CopyCaption(copied: codeCopied) { Text("One-time code") }
                                .font(.system(size: 12)).foregroundStyle(style.muted)
                            HStack(alignment: .center) {
                                OTPCode(code: code, size: 22, urgent: left <= 5)
                                Spacer(minLength: 8)
                                CountdownRing(fraction: remaining, seconds: left, size: 34)
                            }
                        }
                        .animation(.snappy, value: code)
                    }
                    .copyTick(armed: $codeArmed, copied: $codeCopied)
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
    @State var passwordArmed: Int?
    @State var passwordCopied = false
    @State var codeArmed: Int?
    @State var codeCopied = false

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
            Color.panelStrong // the same surface as every other card, in both modes
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

/// A tile's caption that reads "Copied" with a tick for a moment after its copy.
private struct CopyCaption<Label: View>: View {
    let copied: Bool
    @ViewBuilder let label: Label

    var body: some View {
        ZStack(alignment: .leading) {
            label.lineLimit(1).opacity(copied ? 0 : 1).offset(y: copied ? -6 : 0)
            HStack(spacing: 4) {
                Image(systemName: "checkmark").fontWeight(.bold)
                    .symbolEffect(.bounce, value: copied)
                Text("Copied")
            }
            .opacity(copied ? 1 : 0).offset(y: copied ? 0 : 6)
        }
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
    let item: VaultItem
    let field: ItemField
    let reveal: Bool
    @State private var armed: Int?
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: field.label)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Group {
                if field.secret && !reveal {
                    Text(verbatim: String(repeating: "•", count: 10))
                } else if field.secret {
                    DecodingText(field.value)
                } else {
                    Text(verbatim: field.value)
                }
            }
                .font(.system(size: 13, design: field.monospaced ? .monospaced : .default))
                .lineLimit(field.monospaced ? 3 : 2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
            Button {
                armed = model.copyCount
                if field.secret { model.guarded(item) { model.copy(field.value, label: field.label) } } else { model.copy(field.value, label: field.label) }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(Text("Copy \(field.label)"))
            }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(Text("Copy"))
                .copyTick(armed: $armed, copied: $copied)
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
                HStack(spacing: 14) {
                    Label {
                        Text(toast).contentTransition(.opacity)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").symbolEffect(.bounce, options: .speed(1.3), value: toast)
                    }
                    if let action = model.toastAction {
                        Button(action.title) { action.run() }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(.white.opacity(0.2), in: .capsule)
                            .contentShape(.capsule)
                    }
                }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.leading, 18).padding(.trailing, model.toastAction == nil ? 18 : 8)
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

/// In the header while a copied secret waits on the clipboard: a ring draining to the moment it's cleared, the seconds
/// counting down. Clicking clears it now.
private struct ClipboardCountdown: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        ZStack {
            if let clears = model.clipboardClearsAt, let total = model.clipboardHoldSeconds {
                Button { model.clearClipboardNow() } label: {
                    TimelineView(.animation(minimumInterval: 1 / 15)) { context in
                        let remaining = max(0, clears.timeIntervalSince(context.date))
                        let left = Int(remaining.rounded(.up))
                        HStack(spacing: 7) {
                            ZStack {
                                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2)
                                Circle().trim(from: 1 - remaining / total, to: 1)
                                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 13, height: 13)
                            Group {
                                if hovering {
                                    Text("Clear Clipboard Now")
                                } else {
                                    Text("Clipboard clears in \(left) s")
                                        .monospacedDigit()
                                        .contentTransition(.numericText(countsDown: true))
                                }
                            }
                            .transition(.opacity)
                        }
                        .animation(.snappy, value: left)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).frame(height: 32)
                    .modifier(HeaderChrome(shape: .capsule, hovering: hovering))
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .onHover { h in withAnimation(.snappy(duration: 0.15)) { hovering = h } }
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.25), value: model.clipboardClearsAt)
    }
}

/// Colored initial tile; color is derived from the name so it stays stable.
struct Monogram: View {
    let name: String
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    /// The same tile as a site's icon (white, hairline edge), with the initial in dark grey, so letters and logos sit
    /// together as one family. (The tile is always light, so the letter is a fixed dark, not the text colour.)
    var body: some View {
        let dark = scheme == .dark
        Text(name.prefix(1).uppercased())
            .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.62))
            .frame(width: size, height: size)
            .background(dark ? Color(white: 0.96) : .white, in: .rect(cornerRadius: size * 0.29, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous).strokeBorder(.black.opacity(0.08)))
            .accessibilityHidden(true) // decorative: the name is read next to it
    }
}

/// Unlock one locked account in place (from the sidebar), without leaving the vault.
private struct AccountUnlockPane: View {
    @Environment(AppModel.self) private var model
    let account: SavedAccount
    @State private var password = ""
    @State private var usePassword = false
    @State private var refusals = 0

    private var pinMode: Bool { model.isPINEnabled(account.id) && !usePassword }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 24)).foregroundStyle(.secondary)
            Text("Account locked").font(.system(size: 16, weight: .semibold))
            Text(verbatim: "\(account.email) · \(account.serverSummary)")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if model.isTouchIDEnabled(account.id) {
                Button { Task { await model.unlockWithTouchID() } } label: { Label("Unlock with Touch ID", systemImage: "touchid") }
            }
            PasswordField(title: pinMode ? "PIN" : "Master password", text: $password, onSubmit: submit)
                .frame(width: 260)
                .shake(on: refusals)
                .onChange(of: model.errorMessage) { _, message in if message != nil { refusals += 1 } }
            if model.isPINEnabled(account.id) {
                Button(pinMode ? "Use master password" : "Use PIN") { usePassword.toggle(); password = ""; model.errorMessage = nil }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).underline()
            }
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
        let typed = password
        Task {
            if pinMode { await model.unlockWithPIN(typed, accountId: account.id) } else { await model.unlock(password: typed, accountId: account.id) }
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

/// New Folder, in the same form language as the item and Send forms.
private struct NewFolderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var accountId: String?
    @State private var saving = false
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                FormHeader(symbol: "folder.badge.plus", title: "New Folder", subtitle: "Group items; folders can nest.")
                FormCard {
                    if model.sessions.count > 1 {
                        FormField(label: "Account") {
                            SoftMenu(options: model.sessions.map { (String?.some($0.id), $0.account.email) }, selection: $accountId,
                                     accessibilityLabel: "Account")
                        }
                    }
                    FormField(label: "Name", note: "Use / to nest, e.g. Work/Servers.") {
                        TextField("Name", text: $name, prompt: Text("e.g. Work/Servers"))
                            .textFieldStyle(SoftFieldStyle())
                            .focused($focused)
                            .onSubmit(create)
                    }
                }
            }
            .padding(20)
            FormFooter(action: "Create", busy: saving, disabled: trimmed.isEmpty, cancel: { dismiss() }, submit: create)
        }
        .frame(width: 440)
        .background(Color.windowBase)
        .onAppear {
            accountId = model.defaultAccountId
            focused = true
        }
    }

    private func create() {
        guard !trimmed.isEmpty, !saving else { return }
        saving = true
        Task {
            if await model.createFolder(name: trimmed, accountId: accountId) != nil { dismiss() }
            saving = false
        }
    }
}

/// All vaults / My vault / each organization: narrows every list, count and code to one vault.
private struct VaultSwitcher: View {
    @Environment(AppModel.self) private var model

    private var title: String {
        switch model.vaultFilter {
        case .all: String(localized: "All vaults")
        case .personal: String(localized: "My vault")
        case .organization(let id): model.organizations.first { $0.id == id }?.name ?? String(localized: "All vaults")
        }
    }

    private var symbol: String {
        switch model.vaultFilter {
        case .all: "square.stack.3d.up"
        case .personal: "person"
        case .organization: "building.2"
        }
    }

    var body: some View {
        Menu {
            choice(.all, "All vaults", "square.stack.3d.up")
            choice(.personal, "My vault", "person")
            Divider()
            ForEach(model.visibleOrganizations) { org in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { model.vaultFilter = .organization(org.id) }
                } label: {
                    Label { Text(verbatim: org.name) } icon: {
                        Image(systemName: model.vaultFilter == .organization(org.id) ? "checkmark" : "building.2")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 6, style: .continuous))
                Text(verbatim: title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .help(Text("Show one vault"))
        .accessibilityLabel(Text("Vault"))
        .accessibilityValue(Text(verbatim: title))
    }

    private func choice(_ filter: AppModel.VaultFilter, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { model.vaultFilter = filter }
        } label: {
            Label(title, systemImage: model.vaultFilter == filter ? "checkmark" : symbol)
        }
    }
}

/// When the item was made and last edited, when its password last changed, and its earlier passwords.
struct ItemHistoryCard: View {
    @Environment(AppModel.self) private var model
    let item: VaultItem
    @State private var showingPasswords = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Item history").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 8) {
                if let revised = item.revised { row("Last edited", revised) }
                if let created = item.created { row("Created", created) }
                if item.kind == .login, let since = item.passwordSince { row("Password updated", since) }
            }
            if !item.passwordHistory.isEmpty {
                Divider().opacity(0.6)
                Button { model.guarded(item) { showingPasswords = true } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                        Text("Password history")
                        Spacer()
                        Text(item.passwordHistory.count, format: .number).foregroundStyle(.secondary).monospacedDigit()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 13))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panel, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))
        .sheet(isPresented: $showingPasswords) { PasswordHistorySheet(item: item) }
    }

    /// "Tue, 6 Oct 2026 at 22:50:12", and under it how long ago (kept fresh).
    private func row(_ label: LocalizedStringKey, _ date: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 1) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute().second()))
                    .monospacedDigit()
                    .textSelection(.enabled)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.ago(date, now: context.date)).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .help(Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute().second().timeZone())))
        }
        .font(.system(size: 12))
    }

    private static func ago(_ date: Date, now: Date) -> String {
        now.timeIntervalSince(date) < 60 ? String(localized: "Just now") : date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}

/// The passwords an item had before, newest first: hidden until revealed (one at a time or all), then coloured
/// like the generator's, each a click from the clipboard.
struct PasswordHistorySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: VaultItem
    @State private var revealed: Set<Int> = []

    private var entries: [VaultItem.PastPassword] {
        item.passwordHistory.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Password history").font(.system(size: 17, weight: .semibold))
                    Text(verbatim: item.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button(revealed.count == entries.count ? "Hide All" : "Reveal All") {
                    withAnimation(.snappy(duration: 0.2)) {
                        revealed = revealed.count == entries.count ? [] : Set(entries.indices)
                    }
                }
                .buttonStyle(.appSecondarySmall)
            }
            .padding(20)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, past in
                        entry(index, past)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Kept by the server when a password is changed: the last five.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.appSecondary)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
        }
        .frame(width: 460)
    }

    private func entry(_ index: Int, _ past: VaultItem.PastPassword) -> some View {
        let shown = revealed.contains(index)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if shown {
                        ColoredSecret(value: past.password).foregroundStyle(.primary)
                    } else {
                        Text(verbatim: String(repeating: "•", count: 14)).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 14, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
                .contentTransition(.opacity)
                if let date = past.date {
                    Text("Replaced \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(.snappy(duration: 0.2)) { if shown { revealed.remove(index) } else { revealed.insert(index) } }
            } label: {
                Image(systemName: shown ? "eye.slash" : "eye").frame(width: 26, height: 26).contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .help(shown ? Text("Hide") : Text("Reveal"))
            Button { model.copy(past.password, label: String(localized: "Password")) } label: {
                Image(systemName: "doc.on.doc").frame(width: 26, height: 26).contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .help(Text("Copy"))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// "Ask for master password": the item's secrets wait for the master password (or Touch ID).
private struct RepromptSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: AppModel.RepromptRequest
    @State private var password = ""
    @State private var wrong = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                FormHeader(symbol: "lock.shield", title: "Confirm it's you",
                           subtitle: "“\(request.item.name)” asks for your master password.")
                FormCard {
                    PasswordField(title: "Master password", text: $password, prompt: Text("Master password"),
                                  isFocused: $focused.wrappedBinding, onSubmit: submit)
                    if wrong {
                        Label("That's not your master password.", systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(.red)
                    }
                    if AccountStore.isTouchIDEnabled(request.item.accountId) {
                        Button { Task { await touchID() } } label: { Label("Use Touch ID", systemImage: "touchid") }
                            .buttonStyle(.appSecondary)
                    }
                }
            }
            .padding(20)
            FormFooter(action: "Continue", disabled: password.isEmpty, cancel: { dismiss() }, submit: submit)
        }
        .frame(width: 420)
        .background(Color.windowBase)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        if model.verifyMasterPassword(password, accountId: request.item.accountId) {
            model.passReprompt(request)
        } else {
            withAnimation(.snappy) { wrong = true }
            password = ""
        }
    }

    private func touchID() async {
        let keys = await AccountStore.unlockAllWithTouchID([request.item.accountId], reason: String(localized: "show this item"))
        if !keys.isEmpty { model.passReprompt(request) }
    }
}

/// "Are you trying to sign in?": another device asks to sign in with this Mac's approval.
private struct SignInApprovalSheet: View {
    @Environment(AppModel.self) private var model
    let prompt: AppModel.SignInPrompt
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                FormHeader(symbol: "person.badge.key", title: "Are you trying to sign in?",
                           subtitle: "A device wants to sign in to \(prompt.email) without the master password.")
                FormCard {
                    LabeledContent("Device") { Text(verbatim: prompt.request.deviceType).foregroundStyle(.secondary) }
                    LabeledContent("IP address") { Text(verbatim: prompt.request.ipAddress).foregroundStyle(.secondary) }
                    if let created = prompt.request.created.flatMap(VaultDecoder.date) {
                        LabeledContent("Asked") { Text(created, format: .relative(presentation: .named)).foregroundStyle(.secondary) }
                    }
                    FormField(label: "Fingerprint phrase", note: "Approve only if it matches the phrase on the other device.") {
                        Text(verbatim: prompt.fingerprint.joined(separator: "-"))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }
                .font(.system(size: 13))
            }
            .padding(20)
            HStack(spacing: 10) {
                Spacer()
                Button("Deny") { answer(false) }.buttonStyle(.appSecondary).keyboardShortcut(.cancelAction)
                Button {
                    answer(true)
                } label: {
                    HStack(spacing: 6) { if busy { ProgressView().controlSize(.small).tint(.white) }; Text("Approve") }
                }
                .buttonStyle(.appPrimary)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(alignment: .top) { Divider().opacity(0.5) }
        }
        .frame(width: 460)
        .background(Color.windowBase)
        .interactiveDismissDisabled()
    }

    private func answer(_ approve: Bool) {
        busy = true
        Task { await model.answerSignIn(prompt, approve: approve) }
    }
}

/// A sidebar row's label with its icon in the text's quiet secondary colour (the sidebar would tint it brand blue).
struct SidebarLabel: View {
    let title: Text
    let symbol: String
    /// The row's own selection: its icon bounces when it becomes the selected one.
    var tag: SidebarSelection?
    /// A count at the end of the row that rolls to its new value (hidden at 0, like a badge).
    var count: Int?

    @Environment(\.sidebarCurrent) private var current
    @State private var pulse = 0

    init(_ title: LocalizedStringKey, symbol: String, tag: SidebarSelection? = nil, count: Int? = nil) {
        self.title = Text(title); self.symbol = symbol; self.tag = tag; self.count = count
    }
    /// User data (folder and collection names), shown as is.
    init<S: StringProtocol>(verbatim title: S, symbol: String, tag: SidebarSelection? = nil, count: Int? = nil) {
        self.title = Text(title); self.symbol = symbol; self.tag = tag; self.count = count
    }

    private var selected: Bool { tag != nil && tag == current }

    var body: some View {
        Label {
            HStack(spacing: 6) {
                title
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text(count, format: .number)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(count)))
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .animation(.snappy(duration: 0.3), value: count)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
                .symbolEffect(.bounce.down, options: .speed(1.4), value: pulse)
        }
        .onChange(of: selected) { _, now in if now { pulse += 1 } }
        // Something landed here (trashed, archived, starred…): a jump of one or two, not a whole sync arriving.
        .onChange(of: count ?? 0) { old, new in if new > old, new - old <= 2, old > 0 || new == 1 { pulse += 1 } }
    }
}

extension EnvironmentValues {
    /// The sidebar's selection, for its rows (their icons answer being picked).
    @Entry var sidebarCurrent: SidebarSelection?
}

/// A toolbar icon that answers its click with its own motion: the star bounces as it fills, the archive box bounces
/// down as if something dropped in, the pencil wiggles, the trash bounces; a changed symbol morphs into the new one.
/// (Reduce Motion: the symbols only swap.)
struct ToolbarSymbolButton: View {
    enum Effect { case none, bounce, bounceDown, wiggle, wiggleBack }

    let symbol: String
    var effect: Effect = .none
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            animated(Image(systemName: symbol).font(.system(size: 13, weight: .medium)))
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer))) // star ↔ star.fill, eye ↔ eye.slash
                .frame(width: 30, height: 26).contentShape(.rect)
        }
        .buttonStyle(HeaderIconStyle())
    }

    @ViewBuilder private func animated(_ image: some View) -> some View {
        switch effect {
        case .none: image
        case .bounce: image.symbolEffect(.bounce, options: .speed(1.2), value: taps)
        case .bounceDown: image.symbolEffect(.bounce.down, options: .speed(1.2), value: taps)
        case .wiggle: image.symbolEffect(.wiggle, value: taps)
        case .wiggleBack: image.symbolEffect(.wiggle.backward, value: taps)
        }
    }
}

/// At the top of the Trash: when its items are deleted for good, which depends on the server.
private struct TrashNotice: View {
    @Environment(AppModel.self) private var model
    let items: [VaultItem]

    var body: some View {
        let cloud = items.contains { model.isCloud($0.accountId) }
        let own = items.contains { !model.isCloud($0.accountId) }
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
            Group {
                if cloud && own {
                    Text("Bitwarden deletes items for good \(AppModel.cloudTrashDays) days after they go to the Trash. Your own server keeps them until you delete them, unless its admin set it to empty the Trash.")
                } else if cloud {
                    Text("Bitwarden deletes items for good \(AppModel.cloudTrashDays) days after they go to the Trash.")
                } else {
                    Text("Items stay here until you delete them, unless your server's admin set it to empty the Trash after a while.")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.22)))
        .padding(.horizontal, 6)
    }
}

/// "Deleted in 12 days" on a trashed item, orange in its last three days.
private struct PurgeChip: View {
    let date: Date

    var body: some View {
        let days = max(0, Int((date.timeIntervalSinceNow / 86_400).rounded(.up))) // a day and a bit left reads "2 days"
        let soon = days <= 3
        HStack(spacing: 3) {
            Image(systemName: "clock").font(.system(size: 9, weight: .bold))
            Text(days == 0 ? "Deleted today" : "Deleted in ^[\(days) day](inflect: true)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(soon ? Color.orange : .secondary)
        .padding(.horizontal, 6).frame(height: 17)
        .background((soon ? Color.orange : Color.primary).opacity(soon ? 0.14 : 0.07), in: .capsule)
        .help(Text(date.formatted(date: .complete, time: .shortened)))
    }
}
