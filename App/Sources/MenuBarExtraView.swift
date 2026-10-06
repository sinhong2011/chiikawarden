import AppKit
import TriCrypto
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
                    SiteCard()
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
        .onAppear { model.captureForeground() } // the page or app the panel was opened over
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
                        Text(verbatim: Shortcut.current(for: .palette)?.display ?? "⌘K").font(.system(size: 10, weight: .medium, design: .monospaced))
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
            .overlay(Capsule().strokeBorder(searching ? Color.primary.opacity(0.3) : Color.panelEdge, lineWidth: searching ? 1.5 : 1))
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
            FooterButton(symbol: "macwindow", help: "Open Triwarden") { model.bringToFront() }
            FooterButton(symbol: "gearshape", help: "Settings…") { model.showSettings() }
            FooterButton(symbol: "power", help: "Quit Triwarden") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 6)
    }
}

/// What a click copies, and how the panel says so.
enum QuickCopy {
    /// The most useful secret: the password, else the code, else the username.
    @MainActor static func primary(_ item: VaultItem, _ model: AppModel) {
        if let password = item.password { model.guarded(item) { model.copy(password, label: String(localized: "Password")) } }
        else if let totp = item.totp { model.guarded(item) { model.copy(totp.code(), label: String(localized: "Code")) } }
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
                .foregroundStyle(done ? Color.primary : .secondary)
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

/// The logins for the page (or app) the panel was opened over; a click copies the password and goes back there.
private struct SiteCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let context = model.foreground {
            let items = context.items(in: model)
            if !items.isEmpty {
                PanelCard(padding: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if let icon = NSRunningApplication(processIdentifier: context.pid)?.icon {
                                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                            }
                            Text(context.host != nil ? "On \(context.label)" : "For \(context.label)")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.top, 2)
                        TimelineView(.animation(minimumInterval: 1 / 30, paused: !items.contains { $0.totp != nil })) { time in
                            VStack(spacing: 0) {
                                ForEach(items) { item in
                                    QuickRow(item: item, date: time.date) {
                                        NSApp.keyWindow?.orderOut(nil)
                                        model.returnToForeground()
                                    }
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
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
    /// After a click copies: e.g. close the panel and go back to the page it was opened over.
    var afterCopy: (() -> Void)?
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
                        CopyIcon(symbol: "key", help: "Copy Password") { model.guarded(item) { model.copy(password, label: String(localized: "Password")) } }
                    }
                    if let host = item.host, let url = URL(string: "https://\(host)") {
                        CopyIcon(symbol: "arrow.up.right", help: "Open Website") { NSWorkspace.shared.open(url) }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            if let totp = item.totp {
                let left = totp.secondsRemaining(at: date)
                Button { model.guarded(item) { model.copy(totp.code(), label: String(localized: "Code")) } } label: {
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
            if preferCode, let totp = item.totp { model.guarded(item) { model.copy(totp.code(), label: String(localized: "Code")) } } else { QuickCopy.primary(item, model) }
            afterCopy?()
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
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
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
                Image(systemName: "lock.fill").font(.system(size: 20)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 12, style: .continuous))
                Text("Vault locked").font(.system(size: 14, weight: .semibold))
                Button("Unlock…") { model.bringToFront() }
                    .buttonStyle(.appPrimarySmall)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

/// Menu bar glyph: a combination dial — the door's rim, two rings with their notches turned apart (a lock
/// mid-turn; notches lined up under one another read as a podcast mark at this size) and the keyhole.
/// A template image.
enum MenuBarGlyph {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.set()
            let rim = NSBezierPath(ovalIn: NSRect(x: c.x - 8.1, y: c.y - 8.1, width: 16.2, height: 16.2))
            rim.lineWidth = 1.5
            rim.stroke()
            // Each ring's notch is centred on `notch` degrees (AppKit: 0° is right, counter-clockwise); round caps.
            let width: CGFloat = 1.25, gap: CGFloat = 1.8
            for (r, notch): (CGFloat, CGFloat) in [(5.6, 135), (3.35, 315)] {
                let half = asin((gap + width) / 2 / r) * 180 / .pi
                let ring = NSBezierPath()
                ring.appendArc(withCenter: c, radius: r, startAngle: notch + half, endAngle: notch + 360 - half)
                ring.lineWidth = width
                ring.lineCapStyle = .round
                ring.stroke()
            }
            // The keyhole: a round head and a slot widening downwards.
            NSBezierPath(ovalIn: NSRect(x: c.x - 1.05, y: c.y + 0.45 - 1.05, width: 2.1, height: 2.1)).fill()
            let slot = NSBezierPath()
            slot.move(to: NSPoint(x: c.x - 0.425, y: c.y + 0.45))
            slot.line(to: NSPoint(x: c.x + 0.425, y: c.y + 0.45))
            slot.line(to: NSPoint(x: c.x + 0.675, y: c.y - 1.7))
            slot.line(to: NSPoint(x: c.x - 0.675, y: c.y - 1.7))
            slot.close()
            slot.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Triwarden"
        return image
    }()
}
