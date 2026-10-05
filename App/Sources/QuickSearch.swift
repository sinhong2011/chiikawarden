import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: Global hotkey

/// A key + modifiers, stored in Carbon terms (what RegisterEventHotKey wants) with a display string.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    /// ⌘K by default.
    static let paletteDefault = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey), key: "K")

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    /// From a key-down event; nil unless ⌘, ⌥ or ⌃ is held (a bare letter would make typing impossible).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        guard carbon != 0 else { return nil }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        let names: [Int: String] = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
                                    kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→"]
        let key = names[Int(event.keyCode)] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon, key: key)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.key = key
    }

    static var palette: Shortcut {
        get {
            UserDefaults.standard.data(forKey: "paletteShortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
                ?? .paletteDefault
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "paletteShortcut") }
    }
}

/// A system-wide shortcut. Carbon hotkeys work in the sandbox and need no Accessibility permission.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    /// The app's palette hotkey, so Settings can rebind it.
    static weak var palette: GlobalHotKey?

    init(_ shortcut: Shortcut, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, user in
            guard let user else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(user).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, me, &handler)
        register(shortcut)
    }

    /// Stops listening (while Settings records a new shortcut).
    func pause() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    /// Swaps the key combination; false when another app already owns it.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: OSType(0x4357_4b59), id: 1),
                                   GetApplicationEventTarget(), 0, &ref) == noErr
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
    private var resignObserver: NSObjectProtocol?

    init(model: AppModel) { self.model = model }

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Over the vault window when it's in front, else high on the screen.
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
        // Above menu bar extras (status-bar level) so it never opens underneath one, like Spotlight.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // the palette draws its own soft shadow
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        // Clicking anywhere else (another window of ours, the desktop, another app) closes it.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        panel.contentView = NSHostingView(rootView: CommandPalette(close: { [weak self] in self?.close() })
            .environment(model)
            .tint(.brand))
        return panel
    }
}
