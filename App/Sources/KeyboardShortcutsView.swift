import SwiftUI

/// Help › Keyboard Shortcuts (⌘/): every key the app answers to, by where you use it — the vault window, the selected
/// item, search and its filters, the command palette, filling another app, and the system-wide shortcuts (as they're
/// set now). Three balanced columns of grouped cards, keys drawn as keycaps, typed filters as code; a filter field on top.
struct KeyboardShortcutsView: View {
    static let windowID = "keyboard-shortcuts"

    struct Entry: Identifiable {
        enum Kind { case keys, typed }
        /// Keys (`⇧⌘N`), or text to type (`type:card`); alternatives separated by two spaces.
        let keys: String
        let title: LocalizedStringResource
        var kind = Kind.keys
        var id: String { keys + title.key }
    }

    struct Group: Identifiable {
        let title: LocalizedStringResource
        let symbol: String
        let entries: [Entry]
        var id: String { symbol }
    }

    @State private var query = ""
    @FocusState private var filterFocused: Bool

    /// The system-wide shortcuts, as set in Settings › Shortcuts (empty keys: not set).
    private var everywhere: Group {
        Group(title: "Anywhere on your Mac", symbol: "globe", entries: GlobalAction.allCases.map { action in
            Entry(keys: Shortcut.current(for: action)?.display ?? "", title: action.resource)
        })
    }

    static let window = Group(title: "Vault window", symbol: "macwindow", entries: [
        Entry(keys: "⌘K", title: "Command palette"),
        Entry(keys: "⌘F", title: "Search the list"),
        Entry(keys: "⌘G", title: "Generator"),
        Entry(keys: "⌘N", title: "New Login"),
        Entry(keys: "⇧⌘N", title: "New Secure Note"),
        Entry(keys: "⌥⌘N", title: "New Folder…"),
        Entry(keys: "⌘[", title: "Back (narrow windows)"),
        Entry(keys: "⇧⌘I", title: "Import…"),
        Entry(keys: "⇧⌘E", title: "Export Vault…"),
        Entry(keys: "⇧⌘L", title: "Lock Vault"),
        Entry(keys: "⌘,", title: "Settings…"),
    ])

    static let item = Group(title: "Selected item", symbol: "key", entries: [
        Entry(keys: "⌘E", title: "Edit"),
        Entry(keys: "⇧⌘C", title: "Copy Username"),
        Entry(keys: "⌥⌘C", title: "Copy Password"),
        Entry(keys: "⌃⌘C", title: "Copy One-Time Code"),
        Entry(keys: "⌥⌘T", title: "Show Password in Large Type"),
        Entry(keys: "⌘D", title: "Toggle Favorite"),
        Entry(keys: "⌥⌘A", title: "Archive"),
        Entry(keys: "⌘⌫", title: "Move to Trash…"),
        Entry(keys: "↑  ↓", title: "Previous or next item"),
        Entry(keys: "⌘-click  ⇧-click", title: "Pick several items"),
        Entry(keys: "⌘A", title: "Pick all"),
    ])

    static let search = Group(title: "Search and filters", symbol: "line.3.horizontal.decrease.circle", entries: [
        Entry(keys: "type:card", title: "One type of item", kind: .typed),
        Entry(keys: "#Work", title: "A folder and its subfolders", kind: .typed),
        Entry(keys: "is:favorite", title: "Favorites", kind: .typed),
        Entry(keys: "has:otp", title: "Has a one-time code", kind: .typed),
        Entry(keys: "has:passkey", title: "Has a passkey", kind: .typed),
        Entry(keys: "is:weak", title: "Watchtower issues", kind: .typed),
        Entry(keys: "vault:personal", title: "One vault", kind: .typed),
        Entry(keys: "Tab  ↵", title: "Take a suggestion"),
        Entry(keys: "⌫", title: "Take off the last filter"),
        Entry(keys: "Esc", title: "Clear the text, then the filters"),
        Entry(keys: "↓", title: "Into the list"),
    ])

    static let palette = Group(title: "Command palette", symbol: "command", entries: [
        Entry(keys: "↵", title: "Open"),
        Entry(keys: "⌘↵", title: "Copy Password"),
        Entry(keys: "⌥↵", title: "Copy code"),
        Entry(keys: "⇧↵", title: "Open Website"),
        Entry(keys: "→  Tab", title: "All of an item's actions"),
        Entry(keys: ">", title: "Commands only", kind: .typed),
        Entry(keys: "gen 24", title: "A new 24-character password", kind: .typed),
    ])

    static let otherApp = Group(title: "Over another app", symbol: "rectangle.and.hand.point.up.left", entries: [
        Entry(keys: "↵", title: "Type the username and password"),
        Entry(keys: "⌃↵", title: "Type the username"),
        Entry(keys: "⌥↵", title: "Type the password"),
        Entry(keys: "⇧", title: "…and press Return after it"),
    ])

    /// Three columns of about the same height.
    private var columns: [[Group]] {
        [[Self.window, everywhere], [Self.item, Self.palette], [Self.search, Self.otherApp]]
    }

    private func matching(_ group: Group) -> Group? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return group }
        let entries = group.entries.filter {
            String(localized: $0.title).localizedStandardContains(q) || $0.keys.localizedStandardContains(q)
        }
        return entries.isEmpty ? nil : Group(title: group.title, symbol: group.symbol, entries: entries)
    }

    var body: some View {
        let shown = columns.map { $0.compactMap(matching) }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Everything Triwarden answers to. Menu items show theirs too.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    TextField("Filter", text: $query, prompt: Text("Find a shortcut"))
                        .textFieldStyle(.plain).font(.system(size: 12.5))
                        .focused($filterFocused)
                        .onKeyPress(.escape) { guard !query.isEmpty else { return .ignored }; query = ""; return .handled }
                }
                .padding(.horizontal, 10).frame(width: 220, height: 28)
                .background(Color.primary.opacity(0.06), in: .capsule)
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 14)

            Divider().opacity(0.5)

            ScrollView {
                if shown.allSatisfy(\.isEmpty) {
                    ContentUnavailableView.search(text: query).padding(.top, 60)
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, column in
                            VStack(spacing: 18) {
                                ForEach(column) { GroupSection(group: $0) }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 20)
                    .animation(.snappy(duration: 0.2), value: query)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .thinScroller()

            Divider().opacity(0.5)
            Text("Shortcuts that work anywhere change in Settings › Shortcuts; menu shortcuts in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 12)
        }
        .frame(minWidth: 1000, idealWidth: 1040, minHeight: 640, idealHeight: 760)
        .background(Color.windowBase)
        .background { Button("") { filterFocused = true }.keyboardShortcut("f", modifiers: .command).hidden() }
    }
}

/// One group: a small header, then its rows in a card with hairlines between them.
private struct GroupSection: View {
    let group: KeyboardShortcutsView.Group

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(group.title) } icon: { Image(systemName: group.symbol) }
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .frame(height: 14)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().opacity(0.5).padding(.leading, 12) }
                    HStack(alignment: .center, spacing: 12) {
                        Text(entry.title)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if entry.keys.isEmpty {
                            Text("Not set").font(.system(size: 11.5)).foregroundStyle(.tertiary)
                        } else if entry.kind == .typed {
                            Typed(text: entry.keys)
                        } else {
                            KeyCombo(keys: entry.keys)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 2)
            .background(Color.panel, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        }
        .transition(.opacity)
    }
}

/// Keys as keycaps, one cap per key (⇧ ⌘ N); alternatives (two spaces apart) a little further apart, with a thin
/// slash between. "⌘-click" is a cap and the word.
private struct KeyCombo: View {
    let keys: String

    private static let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]

    /// One alternative split into caps, and any trailing word ("click").
    private func caps(_ combo: String) -> (caps: [String], word: String?) {
        var caps: [String] = []
        var rest = Substring(combo)
        while let c = rest.first, Self.modifiers.contains(c) { caps.append(String(c)); rest = rest.dropFirst() }
        if rest.hasPrefix("-") { return (caps, String(rest.dropFirst())) }
        if !rest.isEmpty { caps.append(String(rest)) }
        return (caps, nil)
    }

    var body: some View {
        let alternatives = keys.components(separatedBy: "  ")
        HStack(spacing: 6) {
            ForEach(Array(alternatives.enumerated()), id: \.offset) { index, combo in
                if index > 0 { Text(verbatim: "/").font(.system(size: 11)).foregroundStyle(.quaternary) }
                let parts = caps(combo)
                HStack(spacing: 3) {
                    ForEach(Array(parts.caps.enumerated()), id: \.offset) { _, key in KeyCap(key: key) }
                    if let word = parts.word {
                        Text(verbatim: word).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .fixedSize()
    }
}

/// One key: a small raised tile.
private struct KeyCap: View {
    let key: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(verbatim: key)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, key.count > 1 ? 6 : 0)
            .frame(minWidth: 21, minHeight: 21)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.1) : Color.white)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.18), radius: 0, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}

/// Text you type (a filter, a palette command): code, not keys.
private struct Typed: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 6).frame(minHeight: 21)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 5, style: .continuous))
            .fixedSize()
    }
}

extension GlobalAction {
    /// The title as a resource (for matching the filter as well as showing).
    var resource: LocalizedStringResource {
        switch self {
        case .palette: "Command palette"
        case .fill: "Fill this page or app"
        case .showWindow: "Show Triwarden"
        case .generate: "Copy a new password"
        case .lock: "Lock vault"
        }
    }
}
