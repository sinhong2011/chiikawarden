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
        // Over the vault window when it's in front (⌘K), else high on the screen (⌥Space).
        if NSApp.isActive, let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0 != panel }) {
            let f = window.frame
            panel.setFrameTopLeftPoint(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - 40))
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - f.height * 0.14))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.quickSearchNonce += 1 // resets query and focuses the field
    }

    func close() { panel?.orderOut(nil) }

    private func makePanel() -> QuickSearchPanel {
        let panel = QuickSearchPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 640),
                                     styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                     backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // the palette draws its own soft shadow
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.contentView = NSHostingView(rootView: CommandPalette(close: { [weak self] in self?.close() })
            .environment(model)
            .tint(.brand))
        return panel
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
                    Button { model.lock() } label: { Image(systemName: "lock").accessibilityLabel(Text("Lock")) }
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
                ItemIcon(item: item, size: 22)
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
