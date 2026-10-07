import SwiftUI
import VaultwardenAPI

// The vault window's search: one field over every vault, plus filters that stay on between launches.
// Filters are typed as tokens (`type:card`, `is:favorite`, `has:otp`, `has:passkey`, `is:weak`, `folder:Work` or `#Work`,
// `vault:personal`) or picked from the filter menu; each shows as a chip under the field, and ⌫ in an empty field
// takes the last one off.

extension VaultItem.Kind {
    init(_ type: SearchFilters.ItemType) {
        switch type {
        case .login: self = .login
        case .card: self = .card
        case .identity: self = .identity
        case .note: self = .note
        case .sshKey: self = .sshKey
        }
    }
}

/// One filter as a chip: the search filters' tokens, plus the vault (which the vault switcher holds).
enum SearchChip: Identifiable, Equatable {
    case filter(SearchToken)
    case vault(AppModel.VaultFilter)

    var id: String {
        switch self {
        case .filter(let token): token.text
        case .vault(let v): "vault:" + (v.raw ?? "all")
        }
    }

    @MainActor func label(_ model: AppModel) -> String {
        switch self {
        case .filter(.type(let t)): VaultItem.Kind(t).paletteLabel
        case .filter(.folder(let path)): path
        case .filter(.vault(let name)): name
        case .filter(.favorites): String(localized: "Favorites")
        case .filter(.hasCode): String(localized: "One-time code")
        case .filter(.hasPasskey): String(localized: "Passkey")
        case .filter(.hasIssue): String(localized: "Watchtower issue")
        case .vault(.all): String(localized: "All vaults")
        case .vault(.personal): String(localized: "My vault")
        case .vault(.organization(let id)): model.organizations.first { $0.id == id }?.name ?? String(localized: "Shared vault")
        }
    }

    var symbol: String {
        switch self {
        case .filter(.type(let t)): VaultItem.Kind(t).paletteSymbol
        case .filter(.folder): "folder"
        case .filter(.vault), .vault(.organization): "building.2"
        case .filter(.favorites): "star"
        case .filter(.hasCode): "clock.badge.checkmark"
        case .filter(.hasPasskey): "person.badge.key"
        case .filter(.hasIssue): "exclamationmark.shield"
        case .vault(.all): "square.stack.3d.up"
        case .vault(.personal): "person"
        }
    }
}

extension AppModel {
    /// The chips under the search field: the vault first (when it isn't every vault), then the filters.
    var searchChips: [SearchChip] {
        (vaultFilter == .all ? [] : [.vault(vaultFilter)]) + searchFilters.tokens.map(SearchChip.filter)
    }

    var hasSearchFilters: Bool { vaultFilter != .all || !searchFilters.isEmpty }

    func removeSearchChip(_ chip: SearchChip) {
        switch chip {
        case .filter(let token): searchFilters.remove(token)
        case .vault: vaultFilter = .all
        }
    }

    /// Turns a typed token's filter on; false when it names no folder or vault here (it stays search text).
    func applySearchToken(_ token: SearchToken) -> Bool {
        switch token {
        case .folder(let typed):
            let fold = PaletteQuery.fold
            let names = folders.map(\.name)
            guard let path = names.first(where: { fold($0) == fold(typed) }) ?? names.first(where: { fold($0).hasPrefix(fold(typed)) })
                ?? names.first(where: { fold($0).contains(fold(typed)) }) else { return false }
            searchFilters.folder = path
        case .vault(let typed):
            let v = PaletteQuery.fold(typed)
            if ["all", "any", "every", "everything"].contains(v) {
                vaultFilter = .all
            } else if ["personal", "my", "mine", "me", "own", "private"].contains(v) {
                vaultFilter = .personal
            } else if let org = visibleOrganizations.first(where: { PaletteQuery.fold($0.name) == v })
                        ?? visibleOrganizations.first(where: { PaletteQuery.fold($0.name).hasPrefix(v) }) {
                vaultFilter = .organization(org.id)
            } else {
                return false
            }
        default:
            searchFilters.apply(token)
        }
        return true
    }

    /// Whether an item matches the typed text: every word in its name, username, website or folder.
    static func searchMatches(_ item: VaultItem, _ query: String) -> Bool {
        let words = query.split(separator: " ")
        guard !words.isEmpty else { return true }
        return words.allSatisfy { word in
            item.name.localizedStandardContains(word)
                || (item.username?.localizedStandardContains(word) ?? false)
                || (item.host?.localizedStandardContains(word) ?? false)
                || (item.uri?.localizedStandardContains(word) ?? false)
        }
    }
}

/// The list's search field: a magnifier, the text, a clear button. Finished tokens leave the text for chips; ⌫ in an
/// empty field removes the last chip; Esc clears the text; ↓ moves into the list.
struct VaultSearchField: View {
    @Environment(AppModel.self) private var model
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    var moveToList: () -> Void = {}
    @State private var hovering = false

    private var prompt: Text {
        model.vaultFilter == .all && (!model.visibleOrganizations.isEmpty || model.focusedAccountID == nil && model.accounts.count > 1)
            ? Text("Search all vaults") : Text("Search")
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search", text: $query, prompt: prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(focused)
                .onKeyPress(.escape) {
                    guard !query.isEmpty else { return .ignored }
                    query = ""
                    return .handled
                }
                .onKeyPress(.downArrow) { moveToList(); return .handled }
                .onKeyPress(.delete) {
                    guard query.isEmpty, let last = model.searchChips.last else { return .ignored }
                    withAnimation(.snappy(duration: 0.25)) { model.removeSearchChip(last) }
                    return .handled
                }
                .onSubmit { promote(finishedOnly: false) }
                .onChange(of: query) { promote(finishedOnly: true) }
            if !query.isEmpty {
                Button { query = ""; focused.wrappedValue = true } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(Text("Clear Search"))
                .accessibilityLabel(Text("Clear Search"))
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .modifier(HeaderChrome(shape: .capsule, hovering: hovering || focused.wrappedValue))
        .contentShape(.capsule)
        .onTapGesture { focused.wrappedValue = true }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: query.isEmpty)
        .help(Text("Search by name, username or website. Filter with type:card, is:favorite, has:otp, has:passkey, is:weak, folder:Work or vault:personal."))
    }

    /// Typed tokens become filters (with a space after them, or on Return).
    private func promote(finishedOnly: Bool) {
        guard query.contains(":") || query.contains("#") else { return }
        var applied = false
        let result = SearchToken.extract(from: query, finishedOnly: finishedOnly) { token in
            let ok = withAnimation(.snappy(duration: 0.25)) { model.applySearchToken(token) }
            applied = applied || ok
            return ok
        }
        if applied, result.text != query { query = result.text.trimmingCharacters(in: .whitespaces).isEmpty ? "" : result.text }
    }
}

/// The filter menu beside the search field: every filter, a click away. Filled while any is on.
struct SearchFilterMenu: View {
    @Environment(AppModel.self) private var model

    private func toggle(_ title: LocalizedStringKey, _ symbol: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { set(!on) }
        } label: {
            Label(title, systemImage: on ? "checkmark" : symbol)
        }
    }

    var body: some View {
        @Bindable var model = model
        let active = model.hasSearchFilters
        Menu {
            Section("Type") {
                Button { withAnimation(.snappy(duration: 0.25)) { model.searchFilters.type = nil } } label: {
                    Label("Any type", systemImage: model.searchFilters.type == nil ? "checkmark" : "square.grid.2x2")
                }
                ForEach(SearchFilters.ItemType.allCases, id: \.self) { type in
                    let kind = VaultItem.Kind(type)
                    Button { withAnimation(.snappy(duration: 0.25)) { model.searchFilters.type = type } } label: {
                        Label { Text(verbatim: kind.paletteLabel) } icon: {
                            Image(systemName: model.searchFilters.type == type ? "checkmark" : kind.paletteSymbol)
                        }
                    }
                }
            }
            Section("Show only") {
                toggle("Favorites", "star", model.searchFilters.favorites) { model.searchFilters.favorites = $0 }
                toggle("Has a one-time code", "clock.badge.checkmark", model.searchFilters.hasCode) { model.searchFilters.hasCode = $0 }
                toggle("Has a passkey", "person.badge.key", model.searchFilters.hasPasskey) { model.searchFilters.hasPasskey = $0 }
                toggle("Watchtower issues", "exclamationmark.shield", model.searchFilters.hasIssue) { model.searchFilters.hasIssue = $0 }
            }
            if !model.folders.isEmpty {
                Menu {
                    Button { withAnimation(.snappy(duration: 0.25)) { model.searchFilters.folder = nil } } label: {
                        Label("Any folder", systemImage: model.searchFilters.folder == nil ? "checkmark" : "folder")
                    }
                    Divider()
                    ForEach(model.folders.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { path in
                        Button { withAnimation(.snappy(duration: 0.25)) { model.searchFilters.folder = path } } label: {
                            Label { Text(verbatim: path) } icon: {
                                Image(systemName: model.searchFilters.folder == path ? "checkmark" : "folder")
                            }
                        }
                    }
                } label: {
                    Label("My Folders", systemImage: "folder")
                }
            }
            if !model.visibleOrganizations.isEmpty {
                Menu {
                    vaultChoice(.all, String(localized: "All vaults"), "square.stack.3d.up")
                    vaultChoice(.personal, String(localized: "My vault"), "person")
                    Divider()
                    ForEach(model.visibleOrganizations) { org in
                        vaultChoice(.organization(org.id), org.name, "building.2")
                    }
                } label: {
                    Label("Vault", systemImage: "square.stack.3d.up")
                }
            }
            Divider()
            Button("Clear Filters", systemImage: "xmark.circle") {
                withAnimation(.snappy(duration: 0.25)) { model.clearSearchFilters() }
            }
            .disabled(!active)
        } label: {
            Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .modifier(HeaderChrome(shape: .circle))
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Filters"))
        .accessibilityLabel(Text("Filters"))
        .accessibilityValue(active ? Text("\(model.searchChips.count) on") : Text("Off"))
    }

    private func vaultChoice(_ filter: AppModel.VaultFilter, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { model.vaultFilter = filter }
        } label: {
            Label { Text(verbatim: title) } icon: { Image(systemName: model.vaultFilter == filter ? "checkmark" : symbol) }
        }
    }
}

/// The filters that are on, as chips under the search field; each one's ✕ takes it off, Clear takes them all off.
/// Shown only while a filter is on. Chips pop in and out (the app's snappy spring); with Reduce Motion they fade.
struct SearchFilterBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many items the filters leave, for the count at the end.
    var resultCount: Int

    private var chipTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.7, anchor: .leading).combined(with: .opacity)
    }

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(model.searchChips) { chip in
                        FilterChip(label: chip.label(model), symbol: chip.symbol) {
                            withAnimation(.snappy(duration: 0.25)) { model.removeSearchChip(chip) }
                        }
                        .transition(chipTransition)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            // More chips than fit: they fade out at the end rather than being cut, and scroll sideways.
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 18)
                }
            }
            Button {
                withAnimation(.snappy(duration: 0.25)) { model.clearSearchFilters() }
            } label: {
                Text("Clear").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 9).frame(height: 24)
                    .background(Color.primary.opacity(0.07), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(Text("Clear Filters"))
            .accessibilityLabel(Text("Clear Filters"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Filters, \(resultCount) items"))
    }
}

/// One filter: its symbol, its name, ✕.
private struct FilterChip: View {
    let label: String
    let symbol: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(verbatim: label).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .background(Color.primary.opacity(hovering ? 0.1 : 0), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(Text("Remove"))
            .accessibilityLabel(Text("Remove \(label)"))
        }
        .foregroundStyle(.primary.opacity(0.75))
        .padding(.leading, 8).padding(.trailing, 5).frame(height: 24)
        .frame(maxWidth: 170)
        .background(Color.primary.opacity(0.08), in: .capsule)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}
