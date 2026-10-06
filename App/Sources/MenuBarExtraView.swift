import AppKit
import ChiikawaCrypto
import SwiftUI

/// The menu bar panel: search right here, your favorites, codes and recent items one click from the clipboard,
/// quick actions into the app, a fresh password, the SSH agent, and sync / Watchtower at a glance. Same cards, capsules and type as the main window.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        VStack(spacing: 8) {
            topRow
            if model.isUnlocked {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ShelfCard()
                    QuickActions()
                    GeneratorCard()
                    SSHRow()
                } else {
                    SearchResults(query: query)
                }
            } else {
                LockedCard()
            }
            footer
        }
        .padding(10)
        .frame(width: 380)
        .animation(.snappy(duration: 0.22), value: query.isEmpty)
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                TextField("Search vault", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searching)
                    .disabled(!model.isUnlocked)
                    .onSubmit {
                        // Return copies the top result's password (or the palette takes over for more).
                        if let first = SearchResults.matches(model.items, query).first { QuickCopy.primary(first, model) }
                    }
                if query.isEmpty {
                    Button {
                        NSApp.keyWindow?.orderOut(nil) // the palette takes the panel's place
                        DispatchQueue.main.async { model.openPalette() }
                    } label: {
                        Text(verbatim: Shortcut.palette.display).font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Open the command palette"))
                } else {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(Color.panelStrong, in: .capsule)
            .overlay(Capsule().strokeBorder(searching ? Color.brand.opacity(0.7) : Color.panelEdge, lineWidth: searching ? 1.5 : 1))
            .animation(.easeOut(duration: 0.15), value: searching)

            if model.isUnlocked {
                CircleButton(symbol: "lock", help: "Lock Vault") { model.lock(animated: true) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(model.isOnline ? Color.green : Color.secondary).frame(width: 7, height: 7)
            Group {
                if model.isSyncing {
                    Text("Syncing…")
                } else if let synced = model.lastSynced {
                    Text("Synced \(synced.formatted(.relative(presentation: .named)))")
                } else {
                    Text(model.isUnlocked ? "Offline · saved vault" : "Locked")
                }
            }
            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            .help(Text(verbatim: model.serverDisplayName))
            if model.isUnlocked {
                FooterButton(symbol: "arrow.triangle.2.circlepath", help: "Sync Now", spinning: model.isSyncing) {
                    Task { try? await model.refresh() }
                }
                .disabled(model.isSyncing)
            }
            Spacer()
            FooterButton(symbol: "macwindow", help: "Open Chiikawarden") { model.bringToFront() }
            FooterButton(symbol: "gearshape", help: "Settings…") { model.showSettings() }
        }
        .padding(.horizontal, 6)
    }
}

/// What a click copies, and how the panel says so.
enum QuickCopy {
    /// The most useful secret: the password, else the code, else the username.
    @MainActor static func primary(_ item: VaultItem, _ model: AppModel) {
        if let password = item.password { model.copy(password, label: String(localized: "Password")) }
        else if let totp = item.totp { model.copy(totp.code(), label: String(localized: "Code")) }
        else if let username = item.username { model.copy(username, label: String(localized: "Username")) }
    }
}

/// A card on the panel: the window's raised surface.
private struct PanelCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panelStrong, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.panelEdge))
    }
}

private struct CircleButton: View {
    let symbol: String
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 36, height: 36)
                .background(Color.panelStrong, in: .circle)
                .overlay(Circle().strokeBorder(Color.panelEdge))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }
}

private struct FooterButton: View {
    let symbol: String
    let help: LocalizedStringKey
    var spinning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .symbolEffect(.rotate, isActive: spinning)
                .frame(width: 26, height: 26).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }
}

/// A small icon button that copies, and flashes a check.
private struct CopyIcon: View {
    let symbol: String
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var done = false

    var body: some View {
        Button {
            action()
            withAnimation(.snappy) { done = true }
            Task { try? await Task.sleep(for: .seconds(1.2)); withAnimation(.snappy) { done = false } }
        } label: {
            Image(systemName: done ? "checkmark" : symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(done ? Color.brand : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.06), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }
}

/// How much of a code's period is left, 1…0.
private func codeFraction(_ totp: TOTP, _ date: Date) -> Double {
    let period = Double(totp.period)
    return 1 - date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
}

/// Favorites, codes and recently changed items, a tab each; a click copies, hover shows the rest.
private struct ShelfCard: View {
    enum Tab: Hashable { case favorites, codes, recent }
    @Environment(AppModel.self) private var model
    @AppStorage("menuBarShelf") private var tabRaw = "codes"

    private var tab: Binding<Tab> {
        Binding(get: { switch tabRaw { case "favorites": .favorites; case "recent": .recent; default: .codes } },
                set: { tabRaw = switch $0 { case .favorites: "favorites"; case .recent: "recent"; case .codes: "codes" } })
    }

    private var items: [VaultItem] {
        let live = model.items.filter { !$0.isDeleted && !$0.isArchived }
        switch tab.wrappedValue {
        case .favorites: return Array(live.filter(\.favorite).prefix(6))
        case .codes: return Array(live.filter { $0.totp != nil }.prefix(6))
        case .recent: return Array(live.sorted { ($0.revised ?? .distantPast) > ($1.revised ?? .distantPast) }.prefix(6))
        }
    }

    var body: some View {
        PanelCard(padding: 8) {
            VStack(spacing: 6) {
                AppSegmented(options: [(Tab.favorites, LocalizedStringKey("Favorites")), (.codes, "Codes"), (.recent, "Recent")],
                             selection: tab)
                if items.isEmpty {
                    Text(tab.wrappedValue == .favorites ? "Star items to keep them here." : tab.wrappedValue == .codes
                         ? "Add a code secret to a login to see it here." : "Nothing yet.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: tab.wrappedValue != .codes && !items.contains { $0.totp != nil })) { context in
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                QuickRow(item: item, date: context.date, preferCode: tab.wrappedValue == .codes)
                            }
                        }
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: tabRaw)
    }
}

/// One item: icon and name; its code when it has one; copy buttons on hover. A click copies the main thing.
private struct QuickRow: View {
    @Environment(AppModel.self) private var model
    let item: VaultItem
    let date: Date
    var preferCode = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ItemIcon(item: item, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let username = item.username, !preferCode || item.totp == nil {
                    Text(verbatim: username).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if hovering {
                HStack(spacing: 4) {
                    if let username = item.username {
                        CopyIcon(symbol: "person", help: "Copy Username") { model.copy(username, label: String(localized: "Username")) }
                    }
                    if let password = item.password {
                        CopyIcon(symbol: "key", help: "Copy Password") { model.copy(password, label: String(localized: "Password")) }
                    }
                    if let host = item.host, let url = URL(string: "https://\(host)") {
                        CopyIcon(symbol: "arrow.up.right", help: "Open Website") { NSWorkspace.shared.open(url) }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            if let totp = item.totp {
                let left = totp.secondsRemaining(at: date)
                Button { model.copy(totp.code(), label: String(localized: "Code")) } label: {
                    HStack(spacing: 8) {
                        OTPCode(code: totp.code(at: date), size: 14, urgent: left <= 5)
                        CountdownRing(fraction: codeFraction(totp, date), seconds: left, size: 22)
                    }
                    .fixedSize() // the code keeps its width; the name truncates instead
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(Text("Copy code"))
            }
        }
        .padding(.horizontal, 8).frame(height: 44)
        .background(hovering ? Color.primary.opacity(0.05) : .clear, in: .rect(cornerRadius: 11, style: .continuous))
        .contentShape(.rect)
        .onTapGesture {
            if preferCode, let totp = item.totp { model.copy(totp.code(), label: String(localized: "Code")) } else { QuickCopy.primary(item, model) }
        }
        .onHover { inside in withAnimation(.snappy(duration: 0.15)) { hovering = inside } }
        .contextMenu { ItemContextMenu(item: item) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: item.name))
    }
}

/// Typing in the panel's search: the best matches, each a click from the clipboard.
private struct SearchResults: View {
    @Environment(AppModel.self) private var model
    let query: String

    static func matches(_ items: [VaultItem], _ query: String) -> [VaultItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(items.filter { !$0.isDeleted && !$0.isArchived }
            .filter { $0.name.localizedCaseInsensitiveContains(q) || ($0.username?.localizedCaseInsensitiveContains(q) ?? false)
                || ($0.host?.localizedCaseInsensitiveContains(q) ?? false) }
            .sorted { a, b in
                let ap = a.name.lowercased().hasPrefix(q.lowercased()), bp = b.name.lowercased().hasPrefix(q.lowercased())
                return ap != bp ? ap : a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            .prefix(8))
    }

    var body: some View {
        let results = Self.matches(model.items, query)
        PanelCard(padding: 8) {
            if results.isEmpty {
                Text("No results").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 64)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !results.contains { $0.totp != nil })) { context in
                    VStack(spacing: 0) {
                        ForEach(results) { QuickRow(item: $0, date: context.date) }
                        Text("Return copies the first password · hover for more")
                            .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 6)
                    }
                }
            }
        }
        .transition(.opacity)
    }
}

/// Into the app, straight to the thing: new login, new Send, the generator, Watchtower.
private struct QuickActions: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            tile("plus", "New Login") {
                model.bringToFront()
                model.editing = EditRequest(mode: .create(.login))
            }
            tile("paperplane", "New Send") {
                model.bringToFront()
                model.requestedSection = .sends
                model.composingSend = true
            }
            tile("clock.badge.checkmark", "Codes") {
                model.bringToFront()
                model.requestedSection = .codes
            }
            tile("checkmark.shield", "Watchtower", badge: model.watchtowerIssueCount) {
                model.bringToFront()
                model.requestedSection = .watchtower
            }
        }
    }

    private func tile(_ symbol: String, _ title: LocalizedStringKey, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.brand)
                    .frame(height: 18)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(verbatim: "\(badge)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                                .background(Color.orange, in: .capsule)
                                .offset(x: 12, y: -7)
                        }
                    }
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(Color.panelStrong, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.panelEdge))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(badge > 0 ? Text("^[\(badge) issue](inflect: true)") : Text(verbatim: ""))
    }
}

/// A fresh password or passphrase: switch the kind, regenerate, copy.
private struct GeneratorCard: View {
    enum Kind: Hashable { case password, passphrase }
    @Environment(AppModel.self) private var model
    @AppStorage("menuBarGeneratorKind") private var passphrase = false
    @State private var value = PasswordGenerator.saved.generate()

    var body: some View {
        PanelCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Generator").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    AppSegmented(options: [(false, LocalizedStringKey("Password")), (true, "Passphrase")], selection: $passphrase)
                        .frame(width: 200)
                        .controlSize(.small)
                }
                HStack(spacing: 6) {
                    Text(verbatim: value)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .contentTransition(.opacity)
                    Spacer(minLength: 4)
                    CopyIcon(symbol: "arrow.clockwise", help: "Regenerate password") { regenerate() }
                    CopyIcon(symbol: "doc.on.doc", help: "Copy generated password") {
                        model.copy(value, label: String(localized: "Password"))
                    }
                }
                StrengthMeter(password: value)
            }
        }
        .onChange(of: passphrase) { regenerate() }
        .onAppear { regenerate() }
    }

    private func regenerate() {
        withAnimation(.snappy) { value = passphrase ? PassphraseGenerator().generate() : PasswordGenerator.saved.generate() }
    }
}

/// SSH agent status: on or off, how many keys, the last request.
private struct SSHRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let agent = model.sshAgent!
        let keys = model.items.filter { $0.kind == .sshKey && !$0.isDeleted && !$0.isArchived }.count
        if agent.isRunning || keys > 0 {
            PanelCard(padding: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "terminal").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(agent.isRunning ? Color.green : .secondary)
                        .frame(width: 30, height: 30)
                        .background((agent.isRunning ? Color.green : Color.primary).opacity(0.1), in: .rect(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SSH agent").font(.system(size: 13, weight: .semibold))
                        Group {
                            if !agent.isRunning {
                                Text("Off · ^[\(keys) key](inflect: true) in the vault")
                            } else if let last = agent.recent.first {
                                Text("^[\(keys) key](inflect: true) · \(last.program) used \(last.key) \(last.date.formatted(.relative(presentation: .named)))")
                            } else {
                                Text("^[\(keys) key](inflect: true) ready")
                            }
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(agent.isRunning ? "On" : "Off")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(agent.isRunning ? Color.green : .secondary)
                        .padding(.horizontal, 8).frame(height: 20)
                        .background((agent.isRunning ? Color.green : Color.primary).opacity(0.1), in: .capsule)
                }
            }
        }
    }
}

private struct LockedCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PanelCard {
            VStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 20)).foregroundStyle(Color.brand)
                    .frame(width: 44, height: 44)
                    .background(Color.brand.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
                Text("Vault locked").font(.system(size: 14, weight: .semibold))
                Button("Unlock…") { model.bringToFront() }
                    .buttonStyle(.appPrimarySmall)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

/// Menu bar glyph: the icon's vault handle (ring, crossed spokes with knobs, hub), as a template image.
enum MenuBarGlyph {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - 4.6, y: c.y - 4.6, width: 9.2, height: 9.2))
            ring.lineWidth = 1.6
            ring.stroke()
            let reach: CGFloat = 6.6
            for a in [45.0, 135.0] {
                let r = a * .pi / 180
                let p = NSBezierPath()
                p.move(to: NSPoint(x: c.x + cos(r) * reach, y: c.y + sin(r) * reach))
                p.line(to: NSPoint(x: c.x - cos(r) * reach, y: c.y - sin(r) * reach))
                p.lineWidth = 1.7
                p.lineCapStyle = .round
                p.stroke()
            }
            for a in [45.0, 135.0, 225.0, 315.0] {
                let r = a * .pi / 180
                NSBezierPath(ovalIn: NSRect(x: c.x + cos(r) * reach - 1.6, y: c.y + sin(r) * reach - 1.6, width: 3.2, height: 3.2)).fill()
            }
            NSBezierPath(ovalIn: NSRect(x: c.x - 2.6, y: c.y - 2.6, width: 5.2, height: 5.2)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Chiikawarden"
        return image
    }()
}
