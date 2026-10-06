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

    /// Called from another app: the page's (or app's) logins, which go first; ↵ types the login into it.
    private var context: ForegroundContext? { model.foreground }
    private var siteItems: [VaultItem] {
        guard model.isUnlocked, let context else { return [] }
        let site = context.items(in: model)
        return q.isEmpty ? site : site.filter { CLIBridge.matches($0, q) }
    }

    private var items: [VaultItem] {
        guard model.isUnlocked else { return [] }
        let site = siteItems
        let ids = Set(site.map(\.id))
        let live = model.items.filter { !$0.isDeleted && !$0.isArchived && !ids.contains($0.id) }
        if q.isEmpty { return site + Array((live.filter(\.favorite) + live.filter { !$0.favorite }).prefix(site.isEmpty ? 4 : 2)) }
        return site + Array(live.filter { CLIBridge.matches($0, q) }.prefix(max(2, 6 - site.count)))
    }

    private var commands: [PaletteCommand] {
        let all = Self.commands(model: model, close: close)
        if q.isEmpty { return all.filter { ["new-login", "generator", "watchtower", "lock"].contains($0.id) } }
        return Array(all.filter { $0.matches(q) }.prefix(5))
    }

    private var entries: [Entry] { items.map(Entry.item) + commands.map(Entry.command) }

    var body: some View {
        let dark = scheme == .dark
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(.secondary)
                TextField("Search or run a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .focused($focused)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .onKeyPress(.return, phases: .down) { press in run(press.modifiers); return .handled }
                if let context {
                    ContextChip(context: context)
                } else if model.sessions.count > 1 {
                    Text("\(model.sessions.count) accounts")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Color.primary.opacity(0.06), in: .capsule)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            Divider().opacity(0.6)

            VStack(alignment: .leading, spacing: 1) {
                if !model.isUnlocked {
                    Label("Vault locked: unlock Triwarden to search it", systemImage: "lock.fill")
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(12)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                    let siteCount = siteItems.count
                    if i == 0, siteCount > 0, let context { sectionLabel(context.host != nil ? "On \(context.label)" : "For \(context.label)", first: true) }
                    if i == siteCount, i < items.count { sectionLabel(q.isEmpty ? "Suggestions" : "Items", first: i == 0) }
                    if i == items.count, !commands.isEmpty { sectionLabel("Commands", first: i == 0) }
                    Group {
                        switch entry {
                        case .item(let item):
                            ItemLine(item: item, selected: i == index, returning: context != nil)
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
            .padding(.horizontal, 8).padding(.vertical, 6)
            .animation(.snappy(duration: 0.18), value: index)

            Divider().opacity(0.6)
            HStack(spacing: 16) {
                footerHint("↑↓", "Navigate")
                if let context {
                    footerHint("↵", "Type into \(context.app)")
                    footerHint("⇧", "+ submit")
                } else {
                    footerHint("↵", "Open")
                }
                Spacer()
                footerHint("esc", "Close")
            }
            .padding(.horizontal, 16).frame(height: 36)
        }
        .frame(width: 640)
        .background(.regularMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .background((dark ? Color.black.opacity(0.15) : Color.white.opacity(0.55)), in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(dark ? 0.14 : 0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(dark ? 0.35 : 0.14), radius: 18, y: 8)
        .scaleEffect(x: appeared ? 1 : 0.6, y: appeared ? 1 : 0.8, anchor: .top)
        .opacity(appeared ? 1 : 0)
        .padding(28) // room for the shadow inside the panel
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

    private func sectionLabel(_ title: LocalizedStringKey, first: Bool) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.top, first ? 4 : 10).padding(.bottom, 2)
    }

    private func footerHint(_ keys: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Keycap(keys: keys)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
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
            // Called from another app: type into it, like KeePass's auto-type (↵ both, ⌃↵ username, ⌥↵ password,
            // ⌘↵ code; ⇧ also presses Return). Without Accessibility yet, the password is copied instead.
            if let context, item.kind == .login, item.username != nil || item.password != nil || item.totp != nil {
                let submit = modifiers.contains(.shift)
                let steps: () -> [AutoType.Step] = {
                    var steps: [AutoType.Step]
                    if modifiers.contains(.control) {
                        steps = item.username.map { [.text($0)] } ?? []
                    } else if modifiers.contains(.option) {
                        steps = item.password.map { [.text($0)] } ?? []
                    } else if modifiers.contains(.command) {
                        steps = item.totp.map { [.text($0.code())] } ?? []
                    } else {
                        steps = [item.username.map(AutoType.Step.text), item.username != nil && item.password != nil ? .tab : nil,
                                 item.password.map(AutoType.Step.text)].compactMap { $0 }
                    }
                    if submit, !steps.isEmpty { steps.append(.enter) }
                    return steps
                }
                guard !steps().isEmpty else { return }
                close()
                model.guarded(item) {
                    let fallback = modifiers.contains(.control) ? item.username.map { ($0, String(localized: "Username")) }
                        : item.password.map { ($0, String(localized: "Password")) }
                    model.autoType(steps(), into: context, fallback: fallback.map { (value: $0.0, label: $0.1) })
                }
                return
            }
            if modifiers.contains(.shift), let host = item.host, let url = URL(string: "https://\(host)") {
                NSWorkspace.shared.open(url)
            } else if modifiers.contains(.option), let totp = item.totp {
                model.guarded(item) { model.copy(totp.code(), label: String(localized: "Code")) }
            } else if modifiers.contains(.command), let password = item.password {
                model.copyPassword(item)
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
                PaletteCommand(id: "new-identity", title: String(localized: "New Identity"), symbol: "person.crop.rectangle",
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
                PaletteCommand(id: "import", title: String(localized: "Import…"), symbol: "square.and.arrow.down", shortcut: "⇧⌘I",
                               keywords: ["csv", "json", "chrome", "safari", "firefox", "bitwarden"]) { model.beginImport() },
                PaletteCommand(id: "export", title: String(localized: "Export Vault…"), symbol: "square.and.arrow.up", shortcut: "⇧⌘E",
                               keywords: ["backup", "csv", "json"]) { model.beginExport() },
                PaletteCommand(id: "lock", title: String(localized: "Lock Vault"), symbol: "lock", shortcut: "⇧⌘L") { model.lock(animated: true) },
            ]
        }
        list.append(PaletteCommand(id: "settings", title: String(localized: "Settings…"), symbol: "gearshape", shortcut: "⌘,",
                                   keywords: ["preferences"]) {
            model.showSettings()
        })
        return list
    }
}

/// Spotlight-style selection: a soft neutral wash, no border, no colour slab.
private struct RowHighlight: ViewModifier {
    let selected: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.background {
            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.06))
            }
        }
    }
}

/// A small keycap, used for shortcuts and the hint bar.
struct Keycap: View {
    let keys: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(verbatim: keys)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18)
            .background(Color.primary.opacity(scheme == .dark ? 0.10 : 0.05), in: .rect(cornerRadius: 5, style: .continuous))
    }
}

/// A login row; when highlighted it shows its live code and what the modifier keys do, quietly.
private struct ItemLine: View {
    let item: VaultItem
    let selected: Bool
    /// Called from another app: ↵ types the login into it.
    var returning = false

    var body: some View {
        // The code and its ring sit at the row's centre, beside both the name and the hints below it.
        HStack(alignment: .center, spacing: 12) {
            // Icon, text and code all centre on the whole row (hints included).
            ItemIcon(item: item, size: 32)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text(verbatim: item.username ?? item.host ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                if selected, item.password != nil || item.totp != nil || item.host != nil {
                    HStack(spacing: 14) {
                        if returning {
                            hint("↵", "Fill")
                            if item.username != nil { hint("⌃↵", "Username") }
                            if item.password != nil { hint("⌥↵", "Password") }
                            if item.totp != nil { hint("⌘↵", "Code") }
                        } else {
                            if item.password != nil { hint("⌘↵", "Copy password") }
                            if item.totp != nil { hint("⌥↵", "Copy code") }
                            if item.host != nil { hint("⇧↵", "Open website") }
                        }
                    }
                    .transition(.opacity)
                }
            }
            Spacer(minLength: 8)
            if selected, let totp = item.totp {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let period = Double(totp.period)
                    let left = totp.secondsRemaining(at: ctx.date)
                    HStack(spacing: 12) {
                        OTPCode(code: totp.code(at: ctx.date), size: 17, urgent: left <= 5)
                        CountdownRing(fraction: 1 - ctx.date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period,
                                      seconds: left, size: 30)
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .modifier(RowHighlight(selected: selected))
    }

    private func hint(_ keys: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Keycap(keys: keys)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
    }
}

private struct CommandLine: View {
    let command: PaletteCommand
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbol)
                .font(.system(size: 14))
                .foregroundStyle(selected ? Color.primary : .secondary)
                .frame(width: 32)
            Text(command.title).font(.system(size: 14))
            Spacer()
            if let shortcut = command.shortcut { Keycap(keys: shortcut) }
        }
        .padding(.horizontal, 10).frame(height: 36)
        .modifier(RowHighlight(selected: selected))
    }
}

/// Where the palette was called from: the app's icon, and the page's site once the browser has said.
private struct ContextChip: View {
    let context: ForegroundContext

    var body: some View {
        HStack(spacing: 6) {
            if let icon = NSRunningApplication(processIdentifier: context.pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            Text(verbatim: context.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(Color.primary.opacity(0.06), in: .capsule)
        .animation(.snappy(duration: 0.2), value: context.host)
        .help(Text(verbatim: context.host.map { "\(context.app) · \($0)" } ?? context.app))
    }
}
