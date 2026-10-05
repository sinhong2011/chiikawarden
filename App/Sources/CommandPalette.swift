import AppKit
import SwiftUI

/// One runnable action in the palette.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var shortcut: String?
    var keywords: [String] = []
    let run: @MainActor () -> Void

    func matches(_ q: String) -> Bool {
        title.localizedCaseInsensitiveContains(q) || keywords.contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

/// The command palette (⌘K / ⌘F in the window, the global shortcut from Settings anywhere), after the Liquid search design:
/// a big field, the highlighted login opened up as a dark card with its live code and actions,
/// and a group of commands to run.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let close: () -> Void
    @State private var query = ""
    @State private var index = 0
    @State private var appeared = false
    @FocusState private var focused: Bool

    enum Entry: Identifiable {
        case item(VaultItem)
        case command(PaletteCommand)
        var id: String {
            switch self {
            case .item(let i): "i-" + i.id
            case .command(let c): "c-" + c.id
            }
        }
    }

    private var q: String { query.trimmingCharacters(in: .whitespaces) }

    private var items: [VaultItem] {
        guard model.isUnlocked else { return [] }
        let live = model.items.filter { !$0.isDeleted }
        if q.isEmpty { return Array((live.filter(\.favorite) + live.filter { !$0.favorite }).prefix(4)) }
        return Array(live.filter {
            $0.name.localizedCaseInsensitiveContains(q) || ($0.username?.localizedCaseInsensitiveContains(q) ?? false)
                || ($0.host?.localizedCaseInsensitiveContains(q) ?? false)
        }.prefix(6))
    }

    private var commands: [PaletteCommand] {
        let all = Self.commands(model: model, close: close)
        if q.isEmpty { return all.filter { ["new-login", "generator", "watchtower", "lock"].contains($0.id) } }
        return Array(all.filter { $0.matches(q) }.prefix(5))
    }

    private var entries: [Entry] { items.map(Entry.item) + commands.map(Entry.command) }

    var body: some View {
        let dark = scheme == .dark
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
                TextField("Search or run a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .semibold))
                    .focused($focused)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .onKeyPress(.return, phases: .down) { press in run(press.modifiers); return .handled }
                if model.sessions.count > 1 {
                    Text("\(model.sessions.count) accounts")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Color.primary.opacity(0.06), in: .capsule)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(dark ? Color.white.opacity(0.07) : Color.white.opacity(0.75), in: .rect(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                if !model.isUnlocked {
                    Label("Vault locked: unlock Chiikawarden to search it", systemImage: "lock.fill")
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(12)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                    if i == items.count, !commands.isEmpty {
                        Text("Commands").font(.system(size: 11, weight: .bold)).tracking(0.6).textCase(.uppercase)
                            .foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, i == 0 ? 2 : 8).padding(.bottom, 2)
                    }
                    Group {
                        switch entry {
                        case .item(let item):
                            if i == index { SelectedItemCard(item: item, dark: dark) } else { ItemLine(item: item) }
                        case .command(let command):
                            CommandLine(command: command, selected: i == index)
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)
                    .animation(.spring(duration: 0.4, bounce: 0.2).delay(0.04 * Double(min(i, 6))), value: appeared)
                    .contentShape(.rect)
                    .onTapGesture { index = i; run([]) }
                    .onHover { if $0 { index = i } }
                }
                if model.isUnlocked && entries.isEmpty {
                    Text("Nothing matches “\(q)”").font(.system(size: 13)).foregroundStyle(.secondary).padding(14)
                }
            }
            .padding(4)
            .animation(.spring(duration: 0.3, bounce: 0.15), value: index)
        }
        .padding(8)
        .frame(width: 660)
        .background(.regularMaterial, in: .rect(cornerRadius: 30, style: .continuous))
        .background((dark ? Color.black.opacity(0.2) : Color.white.opacity(0.45)), in: .rect(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(dark ? 0.12 : 0.9), lineWidth: 1))
        .shadow(color: Color(red: 0.12, green: 0.16, blue: 0.35).opacity(0.35), radius: 40, y: 24)
        .scaleEffect(x: appeared ? 1 : 0.6, y: appeared ? 1 : 0.8, anchor: .top)
        .opacity(appeared ? 1 : 0)
        .padding(40) // room for the shadow inside the panel
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The transparent margin is part of the panel: a click there counts as outside.
        .background(Color.black.opacity(0.001).onTapGesture { close() })
        .onChange(of: model.quickSearchNonce, initial: true) {
            query = ""; index = 0; focused = true
            appeared = false
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { appeared = true }
        }
        .onChange(of: query) { index = 0 }
    }

    private func move(_ delta: Int) {
        guard !entries.isEmpty else { return }
        index = (index + delta + entries.count) % entries.count
    }

    private func run(_ modifiers: SwiftUI.EventModifiers) {
        guard entries.indices.contains(index) else { return }
        switch entries[index] {
        case .command(let command):
            close()
            command.run()
        case .item(let item):
            if modifiers.contains(.shift), let host = item.host, let url = URL(string: "https://\(host)") {
                NSWorkspace.shared.open(url)
            } else if modifiers.contains(.option), let totp = item.totp {
                model.copy(totp.code(), label: String(localized: "Code"))
            } else if modifiers.contains(.command), let password = item.password {
                model.copy(password, label: String(localized: "Password"))
            } else {
                model.showItem(item.id)
            }
            close()
        }
    }

    @MainActor
    static func commands(model: AppModel, close: @escaping () -> Void) -> [PaletteCommand] {
        func create(_ kind: AppModel.NewItemKind) { model.bringToFront(); model.editing = EditRequest(mode: .create(kind)) }
        var list: [PaletteCommand] = []
        if model.isUnlocked {
            list += [
                PaletteCommand(id: "new-login", title: String(localized: "New Login"), symbol: "key", shortcut: "⌘N",
                               keywords: ["add", "password", "create"]) { create(.login) },
                PaletteCommand(id: "new-note", title: String(localized: "New Secure Note"), symbol: "note.text", shortcut: "⇧⌘N",
                               keywords: ["add", "create"]) { create(.secureNote) },
                PaletteCommand(id: "new-card", title: String(localized: "New Card"), symbol: "creditcard", keywords: ["add", "credit"]) { create(.card) },
                PaletteCommand(id: "new-identity", title: String(localized: "New Identity"), symbol: "person.text.rectangle",
                               keywords: ["add", "address"]) { create(.identity) },
                PaletteCommand(id: "new-ssh", title: String(localized: "New SSH Key"), symbol: "terminal", keywords: ["add", "ed25519"]) { create(.sshKey) },
                PaletteCommand(id: "new-folder", title: String(localized: "New Folder…"), symbol: "folder.badge.plus", shortcut: "⌥⌘N") {
                    model.bringToFront(); model.promptingNewFolder = true
                },
                PaletteCommand(id: "new-send", title: String(localized: "New Send"), symbol: "paperplane", keywords: ["share", "link"]) {
                    model.bringToFront(); model.requestedSection = .sends; model.composingSend = true
                },
                PaletteCommand(id: "generator", title: String(localized: "Generator"), symbol: "dice", shortcut: "⌘G",
                               keywords: ["random", "generate", "password", "passphrase", "username"]) { model.bringToFront(); model.showingGenerator = true },
                PaletteCommand(id: "codes", title: String(localized: "One-Time Codes"), symbol: "clock.badge.checkmark",
                               keywords: ["totp", "2fa", "otp", "authenticator"]) { model.bringToFront(); model.requestedSection = .codes },
                PaletteCommand(id: "watchtower", title: String(localized: "Watchtower"), symbol: "checkmark.shield",
                               keywords: ["weak", "reused", "breach", "security"]) { model.bringToFront(); model.requestedSection = .watchtower },
                PaletteCommand(id: "sync", title: String(localized: "Sync Now"), symbol: "arrow.triangle.2.circlepath", keywords: ["refresh"]) {
                    Task { try? await model.refresh() }
                },
                PaletteCommand(id: "lock", title: String(localized: "Lock Vault"), symbol: "lock", shortcut: "⇧⌘L") { model.lock() },
            ]
        }
        list.append(PaletteCommand(id: "settings", title: String(localized: "Settings…"), symbol: "gearshape", shortcut: "⌘,",
                                   keywords: ["preferences"]) {
            NSApp.activate()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        })
        return list
    }
}

/// The highlighted login, opened up: name, live code with its countdown, and what ↵ / ⌘↵ / ⌥↵ / ⇧↵ do.
/// A raised light panel like the rest of the app (no dark slab).
private struct SelectedItemCard: View {
    let item: VaultItem
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ItemIcon(item: item, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text(verbatim: item.username ?? item.host ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let totp = item.totp {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(verbatim: totp.displayCode(at: ctx.date))
                            .font(.system(size: 19, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.brand)
                            .contentTransition(.numericText())
                    }
                }
            }
            if let totp = item.totp {
                TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                    let period = Double(totp.period)
                    LevelBar(fraction: 1 - ctx.date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period)
                }
            }
            HStack(spacing: 6) {
                hint("↵", "Open", primary: true)
                if item.password != nil { hint("⌘↵", "Password") }
                if item.totp != nil { hint("⌥↵", "Code") }
                if item.host != nil { hint("⇧↵", "Website") }
            }
        }
        .padding(14)
        .background(dark ? Color.white.opacity(0.10) : Color.white, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.brandFill.opacity(dark ? 0.35 : 0.55), lineWidth: 1.5))
        .shadow(color: Color(red: 0.12, green: 0.16, blue: 0.35).opacity(dark ? 0.35 : 0.12), radius: 14, y: 6)
    }

    /// Keycap + label; the default action is the small primary button.
    private func hint(_ keys: String, _ label: LocalizedStringKey, primary: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: keys).font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background((primary ? Color.white : Color.primary).opacity(primary ? 0.25 : 0.07), in: .rect(cornerRadius: 4))
            Text(label).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(primary ? Color.white : .primary)
        .padding(.horizontal, 10).frame(height: 28)
        .background {
            if primary { Capsule().fill(Color.brandButton) } else { Capsule().fill(Color.primary.opacity(dark ? 0.10 : 0.05)) }
        }
    }
}

private struct ItemLine: View {
    let item: VaultItem

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(item: item, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text(verbatim: item.username ?? item.host ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

private struct CommandLine: View {
    let command: PaletteCommand
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.onBrandFill : Color.brand)
                .frame(width: 32, height: 32)
                .background(selected ? Color.white.opacity(0.35) : Color.brand.opacity(0.10), in: .rect(cornerRadius: 10, style: .continuous))
            Text(command.title).font(.system(size: 14, weight: .semibold))
            Spacer()
            if let shortcut = command.shortcut {
                Text(verbatim: shortcut).font(.system(size: 12, weight: .medium)).foregroundStyle(selected ? Color.onBrandFill.opacity(0.7) : .secondary)
            }
        }
        .foregroundStyle(selected ? Color.onBrandFill : .primary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? Color.brandFill : .clear, in: .rect(cornerRadius: 16, style: .continuous))
    }
}
