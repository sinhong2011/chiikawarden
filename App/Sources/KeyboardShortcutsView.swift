import SwiftUI

/// Help › Keyboard Shortcuts (⌘/): every key the app answers to, by where you use it — the vault window, the selected
/// item, the search and its filters, the command palette, and the system-wide shortcuts (as they're set now).
struct KeyboardShortcutsView: View {
    static let windowID = "keyboard-shortcuts"

    struct Entry: Identifiable {
        let keys: String
        let title: LocalizedStringKey
        var id: String { keys + "\(title)" }
    }

    struct Group: Identifiable {
        let title: LocalizedStringKey
        let symbol: String
        let entries: [Entry]
        var id: String { symbol }
    }

    /// The system-wide shortcuts, as set in Settings › Shortcuts.
    private var everywhere: Group {
        Group(title: "Anywhere on your Mac", symbol: "globe", entries: GlobalAction.allCases.map { action in
            Entry(keys: Shortcut.current(for: action)?.display ?? "", title: action.title)
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
        Entry(keys: "↑ ↓", title: "Previous or next item"),
        Entry(keys: "⌘-click  ⇧-click  ⌘A", title: "Pick several items"),
    ])

    static let search = Group(title: "Search and filters", symbol: "line.3.horizontal.decrease.circle", entries: [
        Entry(keys: "type:card", title: "Logins, cards, identities, notes, SSH keys"),
        Entry(keys: "#Work", title: "A folder and its subfolders"),
        Entry(keys: "is:favorite", title: "Favorites"),
        Entry(keys: "has:otp", title: "Has a one-time code"),
        Entry(keys: "has:passkey", title: "Has a passkey"),
        Entry(keys: "is:weak", title: "Watchtower issues"),
        Entry(keys: "vault:personal", title: "One vault"),
        Entry(keys: "Tab  ↵", title: "Take a suggestion"),
        Entry(keys: "⌫", title: "Take off the last filter"),
        Entry(keys: "Esc", title: "Clear the search"),
        Entry(keys: "↓", title: "Into the list"),
    ])

    static let palette = Group(title: "Command palette", symbol: "command", entries: [
        Entry(keys: "↵", title: "Open"),
        Entry(keys: "⌘↵", title: "Copy Password"),
        Entry(keys: "⌥↵", title: "Copy code"),
        Entry(keys: "⇧↵", title: "Open Website"),
        Entry(keys: "→  Tab", title: "All of an item's actions"),
        Entry(keys: ">", title: "Commands only"),
        Entry(keys: "gen 24", title: "A new 24-character password"),
        Entry(keys: "↵  ⌃↵  ⌥↵", title: "Over another app: type the login, the username, the password"),
        Entry(keys: "⇧", title: "…and press Return after it"),
    ])

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Keyboard Shortcuts").font(.system(size: 22, weight: .bold))
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        GroupCard(group: Self.window)
                        GroupCard(group: everywhere)
                    }
                    VStack(spacing: 16) {
                        GroupCard(group: Self.item)
                        GroupCard(group: Self.palette)
                    }
                    VStack(spacing: 16) {
                        GroupCard(group: Self.search)
                    }
                }
                Text("Change the shortcuts that work anywhere in Settings › Shortcuts; menu shortcuts in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 960, minHeight: 560)
        .background(Color.windowBase)
    }
}

/// One group: its symbol and title, then each key and what it does.
private struct GroupCard: View {
    let group: KeyboardShortcutsView.Group

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(group.title, systemImage: group.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(group.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.title).font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if entry.keys.isEmpty {
                            Text("Off").font(.system(size: 11.5)).foregroundStyle(.tertiary) // not set in Settings
                        } else {
                            KeyCaps(keys: entry.keys)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panel, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// Keys as small caps-like tiles; double spaces separate alternatives.
private struct KeyCaps: View {
    let keys: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.components(separatedBy: "  ").enumerated()), id: \.offset) { _, key in
                Text(verbatim: key)
                    .font(.system(size: 11.5, weight: .medium, design: key.contains(":") || key.hasPrefix("#") ? .monospaced : .default))
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 20)
                    .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }
        }
        .fixedSize()
    }
}
