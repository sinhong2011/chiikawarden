import AppKit

/// Keeps Triwarden's windows out of screen sharing, recordings and screenshots (Settings › Security › Privacy), so a
/// revealed password doesn't go out with a video call.
@MainActor
enum CaptureShield {
    private static var observer: Any?

    /// Shields every window now, and each new one as it appears.
    static func start() {
        applyAll()
        guard observer == nil else { return }
        // Fires when a window comes on screen (and when it's covered or uncovered): new panels, sheets, Settings.
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil,
                                                          queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { window.map(apply) }
        }
    }

    static func applyAll() { NSApp.windows.forEach(apply) }

    static func apply(_ window: NSWindow) {
        // The demo vault has nothing to hide, and UI tests drive it.
        let hide = UserDefaults.standard.bool(forKey: Pref.hideFromCapture) && !CommandLine.arguments.contains("--demo")
        window.sharingType = hide ? .none : .readOnly
    }
}
