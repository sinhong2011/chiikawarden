import TriCrypto
import SwiftUI

/// Sidebar › One-Time Codes: every code, live, click to copy. Grouped by vault when there are shared ones, sorted by
/// name or by recent use (favorites first, if wanted), and narrowed by typing. One clock drives every card, four ticks a
/// second; only the cards on screen are built; the dot between the halves stays still.
struct CodesPane: View {
    @Environment(AppModel.self) private var model
    @State private var copiedID: String?
    @State private var query = ""
    /// The tag picked in the header: every code, favorites, or one vault ("personal" or an organization id).
    @State private var scope = Scope.all

    enum Scope: Hashable { case all, favorites, vault(String) }
    @AppStorage("codesSort") private var sortRaw = CodesSort.name.rawValue
    @AppStorage("codesFavoritesFirst") private var favoritesFirst = true
    @AppStorage("codesGroupByVault") private var groupByVault = true

    enum CodesSort: String, CaseIterable, Identifiable {
        case name, recent
        var id: Self { self }
        var title: LocalizedStringKey { self == .name ? "Name" : "Recently Used" }
        var symbol: String { self == .name ? "textformat" : "clock.arrow.circlepath" }
    }

    private var sort: CodesSort { CodesSort(rawValue: sortRaw) ?? .name }

    /// Every live code, narrowed by the typed filter (not by the tag: the tags count from this).
    private var base: [VaultItem] {
        model.vaultItems.filter { !$0.isDeleted && !$0.isArchived && $0.totp != nil && AppModel.searchMatches($0, query) }
    }

    private func inScope(_ item: VaultItem, _ scope: Scope) -> Bool {
        switch scope {
        case .all: true
        case .favorites: item.favorite
        case .vault(let key): (item.organizationId ?? AppModel.VaultFilter.personalKey) == key
        }
    }

    private var items: [VaultItem] {
        let all = base.filter { inScope($0, scope) }
        let recent = Dictionary(PaletteRecents.ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return all.sorted { a, b in
            if favoritesFirst, a.favorite != b.favorite { return a.favorite }
            if sort == .recent {
                let ra = recent[a.id] ?? .max, rb = recent[b.id] ?? .max
                if ra != rb { return ra < rb }
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// The codes by vault (My vault, then each shared vault), or all together.
    private var groups: [(title: String?, items: [VaultItem])] {
        let list = items
        guard groupByVault, scope == .all, !model.visibleOrganizations.isEmpty else { return [(nil, list)] }
        var out: [(String?, [VaultItem])] = [(String(localized: "My vault"), list.filter { $0.organizationId == nil })]
        out += model.visibleOrganizations.map { org in (org.name, list.filter { $0.organizationId == org.id }) }
        return out.filter { !$0.1.isEmpty }
    }

    var body: some View {
        let groups = groups
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if groups.allSatisfy({ $0.items.isEmpty }) {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "No one-time codes" : "No Results",
                              systemImage: query.isEmpty ? "clock.badge.checkmark" : "magnifyingglass")
                    } description: {
                        if query.isEmpty { Text("Add a code secret to a login to see it here.") }
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(groups, id: \.title) { group in
                        Section {
                            // One clock for every card, four ticks a second, aligned: a tick re-lays out the window once,
                            // however many codes are showing (a clock per card multiplied that). Animating the rings
                            // between ticks instead costs more: SwiftUI lays out every frame of an animation.
                            TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 0.25)) { context in
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                                    ForEach(group.items) { item in card(item, date: context.date) }
                                }
                            }
                        } header: {
                            if let title = group.title {
                                HStack(spacing: 6) {
                                    Text(verbatim: title).font(.system(size: 13, weight: .semibold))
                                    Text(group.items.count, format: .number).font(.system(size: 12, weight: .medium))
                                        .monospacedDigit().foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(.leading, VaultView.pageInset)
            .padding(.vertical, 24)
            .animation(.snappy(duration: 0.25), value: query)
            .animation(.snappy(duration: 0.25), value: sortRaw)
            .animation(.snappy(duration: 0.25), value: favoritesFirst)
            .animation(.snappy(duration: 0.25), value: groupByVault)
        }
        .modifier(SideOverflowClip())
        .thinScroller()
    }

    /// The tags: All, Favorites, then each vault (when there are shared ones), each with its count; then the filter
    /// as a pill and the sort menu. The page's name is the sidebar's; the header is for narrowing.
    private var header: some View {
        let list = base
        return HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    tag(.all, String(localized: "All"), "clock.badge.checkmark", list.count)
                    let favorites = list.filter(\.favorite).count
                    if favorites > 0 { tag(.favorites, String(localized: "Favorites"), "star", favorites) }
                    if !model.visibleOrganizations.isEmpty {
                        tag(.vault(AppModel.VaultFilter.personalKey), String(localized: "My vault"), "person",
                            list.filter { $0.organizationId == nil }.count)
                        ForEach(model.visibleOrganizations) { org in
                            tag(.vault(org.id), org.name, "building.2", list.filter { $0.organizationId == org.id }.count)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                TextField("Filter", text: $query, prompt: Text("Filter codes"))
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .onKeyPress(.escape) { guard !query.isEmpty else { return .ignored }; query = ""; return .handled }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear Search"))
                }
            }
            .padding(.horizontal, 12).frame(width: 200, height: 32)
            .modifier(HeaderChrome(shape: .capsule))
            Menu {
                Picker("Sort By", selection: $sortRaw) {
                    ForEach(CodesSort.allCases) { Label($0.title, systemImage: $0.symbol).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                Toggle("Favorites First", isOn: $favoritesFirst)
                if !model.visibleOrganizations.isEmpty {
                    Toggle("Group by Vault", isOn: $groupByVault)
                }
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
            .help(Text("Sort and group"))
            .accessibilityLabel(Text("Sort"))
        }
        .padding(.trailing, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("One-Time Codes"))
        .animation(.snappy(duration: 0.25), value: scope)
    }

    /// One tag: picked, it's a solid pill (the brand fill, white text); otherwise a soft one.
    private func tag(_ value: Scope, _ title: String, _ symbol: String, _ count: Int) -> some View {
        let picked = scope == value
        return Button { withAnimation(.snappy(duration: 0.25)) { scope = value } } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(verbatim: title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(count, format: .number).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .opacity(picked ? 0.8 : 0.55)
                    .contentTransition(.numericText(value: Double(count)))
            }
            .foregroundStyle(picked ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.75)))
            .padding(.horizontal, 12).frame(height: 32)
            .background {
                if picked {
                    Capsule().fill(Color.brand) // a fill, never brand-coloured text or icons
                        .shadow(color: Color.brand.opacity(0.3), radius: 6, y: 2)
                }
            }
            .modifier(TagChrome(picked: picked))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func card(_ item: VaultItem, date: Date) -> some View {
        Group {
            if let totp = item.totp {
                CodeCard(item: item, totp: totp, date: date, copied: copiedID == item.id) {
                    model.guarded(item) { model.copy(totp.code(at: .now), label: String(localized: "Code")) }
                    PaletteRecents.note(item.id) // "Recently Used" follows what you copy here too
                    withAnimation(.snappy) { copiedID = item.id }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        if copiedID == item.id { withAnimation(.snappy) { copiedID = nil } }
                    }
                }
                .contextMenu { ItemContextMenu(item: item) }
            }
        }
    }
}

/// One code at the page's clock: the code, its seconds and its ring.
private struct CodeCard: View {
    let item: VaultItem
    let totp: TOTP
    /// The page's clock.
    let date: Date
    let copied: Bool
    let copy: () -> Void
    @State private var hovering = false

    var body: some View {
        let period = Double(totp.period)
        content(code: totp.code(at: date), left: totp.secondsRemaining(at: date),
                fraction: 1 - date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period)
    }

    private func content(code: String, left: Int, fraction: Double) -> some View {
        Button(action: copy) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ItemIcon(item: item, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(verbatim: item.username ?? item.host ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    // Copy state as an icon: appears on hover, turns to a check once copied.
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(copied ? Color.primary : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .opacity(copied || hovering ? 1 : 0)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .center) {
                    OTPCode(code: code, size: 28, urgent: left <= 5, breathing: false)
                    Spacer(minLength: 8)
                    CountdownRing(fraction: fraction, seconds: left, size: 40)
                }
            }
            .padding(16)
            .background(Color.panelStrong.opacity(hovering ? 1 : 0.85), in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(copied ? Color.brand.opacity(0.6) : Color.panelEdge, lineWidth: copied ? 1.5 : 1))
            .shadow(color: Color(red: 0.12, green: 0.16, blue: 0.35).opacity(hovering ? 0.12 : 0.06), radius: hovering ? 14 : 8, y: 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(verbatim: "\(item.name), \(code)"))
        .accessibilityHint(Text("Copies the code"))
    }
}


/// An unpicked tag's soft glass (the header's chrome); a picked one has its own fill.
private struct TagChrome: ViewModifier {
    let picked: Bool
    func body(content: Content) -> some View {
        if picked { content } else { content.modifier(HeaderChrome(shape: .capsule)) }
    }
}
