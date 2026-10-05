import AppKit
import SwiftUI

extension NSColor {
    /// Brand blue, tuned for WCAG contrast: 4.5:1 as text on the window background in light mode (#3A63E8),
    /// and on dark panels (#6390FF). Mirrors AccentColor in the app's asset catalog.
    static let chiikawardenBrand = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x63 / 255, green: 0x90 / 255, blue: 0xFF / 255, alpha: 1)
            : NSColor(srgbRed: 0x3A / 255, green: 0x63 / 255, blue: 0xE8 / 255, alpha: 1)
    }
}
