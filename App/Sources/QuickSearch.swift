import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: Global hotkey

/// ⌥Space anywhere. Carbon hotkeys work in the sandbox and need no Accessibility permission.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(optionKey), action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, user in
            guard let user else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(user).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, me, &handler)
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x4357_4b59), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}

// MARK: Panel

/// A floating, borderless panel that can take key focus without activating a full window.
final class QuickSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickSearchController {
    private var panel: QuickSearchPanel?
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - f.height * 0.18))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.quickSearchNonce += 1 // resets query and focuses the field
    }

    func close() { panel?.orderOut(nil) }

    private func makePanel() -> QuickSearchPanel {
        let panel = QuickSearchPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                                     styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                     backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.contentView = NSHostingView(rootView: QuickSearchView(close: { [weak self] in self?.close() })
            .environment(model)
            .tint(.brand))
        return panel
    }
}

// MARK: View

struct QuickSearchView: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private var results: [VaultItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let base = q.isEmpty ? model.items.filter(\.favorite) + model.items.filter { !$0.favorite } : model.items.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || ($0.username?.localizedCaseInsensitiveContains(q) ?? false)
                || ($0.host?.localizedCaseInsensitiveContains(q) ?? false)
        }
        return Array(base.prefix(7))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(.secondary)
                TextField("Search vault", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .medium))
                    .focused($focused)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .onKeyPress(.return, phases: .down) { press in act(press.modifiers); return .handled }
                    .disabled(!model.isUnlocked)
            }
            .padding(.horizontal, 20)
            .frame(height: 60)

            Divider()

            if !model.isUnlocked {
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill").font(.system(size: 22)).foregroundStyle(.secondary)
                    Text("Vault locked").font(.system(size: 15, weight: .semibold))
                    Button("Open Chiikawarden to unlock") {
                        close()
                        NSApp.activate()
                        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                    }
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if results.isEmpty {
                Text("No results").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, item in
                        QuickRow(item: item, isSelected: i == index)
                            .onTapGesture { index = i; act([]) }
                    }
                }
                .padding(8)
            }

            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 16) {
                hint("↵", "Copy password")
                hint("⌥↵", "Copy code")
                hint("⌘↵", "Open website")
                Spacer()
                hint("esc", "Close")
            }
            .padding(.horizontal, 18)
            .frame(height: 36)
        }
        .frame(width: 640, height: 420)
        .background(Color.windowBase, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .onChange(of: model.quickSearchNonce, initial: true) { query = ""; index = 0; focused = true }
        .onChange(of: query) { index = 0 }
    }

    private func hint(_ key: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: key).font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.primary.opacity(0.07), in: .rect(cornerRadius: 4))
            Text(label)
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        index = (index + delta + results.count) % results.count
    }

    private func act(_ modifiers: SwiftUI.EventModifiers) {
        guard results.indices.contains(index) else { return }
        let item = results[index]
        if modifiers.contains(.command), let host = item.host, let url = URL(string: "https://\(host)") {
            NSWorkspace.shared.open(url)
        } else if modifiers.contains(.option), let totp = item.totp {
            model.copy(totp.code(), label: String(localized: "Code"))
        } else if let password = item.password {
            model.copy(password, label: String(localized: "Password"))
        } else if let first = item.fields.first {
            model.copy(first.value, label: first.label)
        } else {
            return
        }
        close()
    }
}

private struct QuickRow: View {
    let item: VaultItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Monogram(name: item.name, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if let sub = item.username ?? item.host {
                    Text(verbatim: sub).font(.system(size: 12)).foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary).lineLimit(1)
                }
            }
            Spacer()
            if let totp = item.totp {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(verbatim: totp.displayCode(at: ctx.date)).font(.system(size: 14, weight: .semibold, design: .monospaced))
                }
            }
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 10).frame(height: 44)
        .background(isSelected ? Color.brand : .clear, in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
    }
}

// MARK: Menu bar

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: "Chiikawarden").font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.isUnlocked {
                    Button { model.lock() } label: { Image(systemName: "lock") }
                        .buttonStyle(.borderless).help(Text("Lock Vault"))
                }
            }

            if model.isUnlocked {
                let codes = model.items.filter(\.hasTOTP)
                if !codes.isEmpty {
                    Text("Verification Codes").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        VStack(spacing: 2) {
                            ForEach(codes.prefix(6)) { item in
                                if let totp = item.totp {
                                    MenuRow(item: item, trailing: totp.displayCode(at: ctx.date)) {
                                        model.copy(totp.code(), label: String(localized: "Code"))
                                    }
                                }
                            }
                        }
                    }
                }
                let favorites = model.items.filter { $0.favorite && $0.password != nil }
                if !favorites.isEmpty {
                    Text("Favorites").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    VStack(spacing: 2) {
                        ForEach(favorites.prefix(5)) { item in
                            MenuRow(item: item, trailing: nil) {
                                if let pw = item.password { model.copy(pw, label: String(localized: "Password")) }
                            }
                        }
                    }
                }
            } else {
                Text("Vault locked").foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button("Open Chiikawarden") {
                    NSApp.activate()
                    NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct MenuRow: View {
    let item: VaultItem
    let trailing: String?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Monogram(name: item.name, size: 22)
                Text(item.name).font(.system(size: 13)).lineLimit(1)
                Spacer()
                if let trailing {
                    Text(verbatim: trailing).font(.system(size: 13, weight: .medium, design: .monospaced))
                } else {
                    Image(systemName: "doc.on.doc").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).frame(height: 30)
            .background(hovered ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
