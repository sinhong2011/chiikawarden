import AppKit
import SwiftUI

extension NSColor {
    /// Brand sky blue, from the tail of the mascot (tint #CBE4F6). Tuned for WCAG contrast: #2371A9 in light
    /// mode (4.7:1 as text on the window, 5.2:1 under white text), #47A0E1 in dark mode (4.9–5.9:1 on panels).
    /// Mirrors AccentColor in the app's asset catalog.
    static let chiikawardenBrand = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x47 / 255, green: 0xA0 / 255, blue: 0xE1 / 255, alpha: 1)
            : NSColor(srgbRed: 0x23 / 255, green: 0x71 / 255, blue: 0xA9 / 255, alpha: 1)
    }
}

extension Color {
    /// The tail itself: a pale sky tint for washes and soft fills (deep blue in dark mode).
    static let brandTint = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x1B / 255, green: 0x3A / 255, blue: 0x52 / 255, alpha: 1)
            : NSColor(srgbRed: 0xCB / 255, green: 0xE4 / 255, blue: 0xF6 / 255, alpha: 1)
    })
}
