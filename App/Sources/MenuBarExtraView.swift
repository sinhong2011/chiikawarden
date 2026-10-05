import AppKit
import ChiikawaCrypto
import SwiftUI

/// The menu bar extra, after the MenuBar design: search, a featured login with its live code, every code,
/// a fresh password, SSH agent status and sync / Watchtower at a glance.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 6) {
            topRow
            if model.isUnlocked {
                if let featured { FeaturedCard(item: featured) }
                CodesSection()
                GeneratorRow()
                SSHRow()
            } else {
                LockedCard()
            }
            footer
        }
        .padding(8)
        .frame(width: 372)
    }

    /// First favourite with a code, else any favourite login, else any code.
    private var featured: VaultItem? {
        let live = model.items.filter { !$0.isDeleted && $0.kind == .login }
        return live.first { $0.favorite && $0.totp != nil } ?? live.first { $0.favorite } ?? live.first { $0.totp != nil }
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            Button {
                // Close the menu bar panel first so the palette takes its place.
                NSApp.keyWindow?.orderOut(nil)
                DispatchQueue.main.async { model.openPalette() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                    Text("Search vault").font(.system(size: 13))
                    Spacer()
                    Text(verbatim: "⌥Space").font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).frame(height: 36)
                .background(Pill.fill(scheme), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            if model.isUnlocked {
                Button { model.lock() } label: {
                    Image(systemName: "lock").font(.system(size: 13, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(Pill.fill(scheme), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(Text("Lock Vault"))
                .accessibilityLabel(Text("Lock Vault"))
            }
        }
        .padding(4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.isOnline ? Color.green : Color.secondary).frame(width: 7, height: 7)
            Group {
                if let synced = model.lastSynced {
                    Text("Synced \(synced.formatted(.relative(presentation: .named)))")
                } else {
                    Text(model.isUnlocked ? "Offline · saved vault" : "Locked")
                }
            }
            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            .help(Text(verbatim: model.serverDisplayName))
            Spacer()
            if model.isUnlocked, model.watchtowerIssueCount > 0 {
                Button {
                    model.bringToFront()
                    model.requestedSection = .watchtower
                } label: {
                    Text("^[\(model.watchtowerIssueCount) issue](inflect: true)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.54, green: 0.32, blue: 0))
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Color(red: 1, green: 0.95, blue: 0.85), in: .capsule)
                }
                .buttonStyle(.plain)
                .help(Text("Open Watchtower"))
            }
            footerButton("macwindow", help: "Open Chiikawarden") { model.bringToFront() }
            footerButton("gearshape", help: "Settings…") {
                NSApp.activate()
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 2)
    }

    private func footerButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 28, height: 28).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }
}

private enum Pill {
    static func fill(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.10) : .white.opacity(0.85) }
}

/// The dark card: one login with its live code and quick copy buttons.
private struct FeaturedCard: View {
    @Environment(AppModel.self) private var model
    let item: VaultItem

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                Label(item.host ?? String(localized: "Favorite"), systemImage: item.host == nil ? "star" : "globe")
                    .font(.system(size: 11, weight: .bold)).tracking(0.6).textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 12) {
                    ItemIcon(item: item, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
                        Text(verbatim: item.username ?? "").font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                    Spacer()
                    if let totp = item.totp {
                        let period = Double(totp.period)
                        let remaining = 1 - context.date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
                        ZStack {
                            Circle().stroke(.white.opacity(0.18), lineWidth: 3)
                            Circle().trim(from: 1 - remaining, to: 1)
                                .stroke(Color(red: 0.55, green: 0.78, blue: 0.95), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 26, height: 26)
                        Text(verbatim: totp.displayCode(at: context.date))
                            .font(.system(size: 19, weight: .semibold, design: .monospaced))
                            .contentTransition(.numericText())
                    }
                }
                HStack(spacing: 6) {
                    if let password = item.password {
                        cardButton("Password", prominent: true) { model.copy(password, label: String(localized: "Password")) }
                    }
                    if let totp = item.totp {
                        cardButton("Code", prominent: item.password == nil) { model.copy(totp.code(), label: String(localized: "Code")) }
                    }
                    if let host = item.host, let url = URL(string: "https://\(host)") {
                        cardButton("Open", prominent: false) { NSWorkspace.shared.open(url) }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(Color(red: 0.06, green: 0.17, blue: 0.27), in: .rect(cornerRadius: 18, style: .continuous))
            .shadow(color: Color(red: 0.05, green: 0.15, blue: 0.25).opacity(0.5), radius: 14, y: 8)
        }
    }

    private func cardButton(_ title: LocalizedStringKey, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: prominent ? .bold : .semibold))
                .foregroundStyle(prominent ? Color(red: 0.06, green: 0.17, blue: 0.27) : .white)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(prominent ? Color.white : Color.white.opacity(0.14), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// Every code, with one shared countdown bar; a click copies and says so.
private struct CodesSection: View {
    @Environment(AppModel.self) private var model
    @State private var copiedID: String?

    var body: some View {
        let items = model.items.filter { !$0.isDeleted && $0.totp != nil }.prefix(5)
        if !items.isEmpty {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Text("Codes").font(.system(size: 11, weight: .bold)).tracking(0.6).textCase(.uppercase)
                        .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 4)
                    ForEach(Array(items)) { item in
                        if let totp = item.totp {
                            CodeRow(item: item, code: totp.displayCode(at: context.date), copied: copiedID == item.id) {
                                model.copy(totp.code(), label: String(localized: "Code"))
                                withAnimation(.snappy) { copiedID = item.id }
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    if copiedID == item.id { withAnimation(.snappy) { copiedID = nil } }
                                }
                            }
                        }
                    }
                    let period = 30.0
                    let remaining = 1 - context.date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
                    GeometryReader { g in
                        Capsule().fill(Color.primary.opacity(0.08))
                            .overlay(alignment: .leading) { Capsule().fill(Color.brand).frame(width: g.size.width * remaining) }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 10).padding(.top, 6)
                }
                .padding(.horizontal, 4).padding(.top, 6).padding(.bottom, 2)
            }
        }
    }
}

private struct CodeRow: View {
    let item: VaultItem
    let code: String
    let copied: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ItemIcon(item: item, size: 30)
                Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(copied ? String(localized: "Copied") : code)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(copied ? Color.brand : .primary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(copied ? Color.brand.opacity(0.10) : hovering ? Color.primary.opacity(0.06) : .clear,
                        in: .rect(cornerRadius: 14, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A fresh password, regenerate or copy.
private struct GeneratorRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var password = PasswordGenerator.saved.generate()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.horizontal").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.brand)
            Text(verbatim: password)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            iconButton("arrow.clockwise", help: "Regenerate password") {
                withAnimation(.snappy) { password = PasswordGenerator.saved.generate() }
            }
            iconButton("doc.on.doc", help: "Copy generated password") {
                model.copy(password, label: String(localized: "Password"))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Pill.fill(scheme).opacity(0.85), in: .rect(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 4)
    }

    private func iconButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }
}

/// SSH agent status: on or off, how many keys, the last request.
private struct SSHRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let agent = model.sshAgent!
        let keys = model.items.filter { $0.kind == .sshKey && !$0.isDeleted }.count
        if agent.isRunning || keys > 0 {
            HStack(spacing: 10) {
                Image(systemName: "terminal").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(agent.isRunning ? Color.green : .secondary)
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
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Circle().fill(agent.isRunning ? Color.green : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                    .background(Circle().fill((agent.isRunning ? Color.green : .clear).opacity(0.18)).frame(width: 16, height: 16))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Pill.fill(scheme).opacity(0.85), in: .rect(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 4)
        }
    }
}

private struct LockedCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 22)).foregroundStyle(.secondary)
            Text("Vault locked").font(.system(size: 14, weight: .semibold))
            Button("Unlock…") { model.bringToFront() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
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
