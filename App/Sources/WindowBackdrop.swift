import SwiftUI

/// The window's backdrop, after the Liquid design: a soft pastel wash (pink top-left, peach top-right,
/// mint bottom-right, lavender bottom-left) under translucent panels. Dark mode keeps the same glows,
/// faint, on deep navy.
struct WindowBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            (dark ? Color(red: 0.07, green: 0.08, blue: 0.13) : Color(red: 0.95, green: 0.95, blue: 0.98))
            glow(Color(red: 0.97, green: 0.72, blue: 0.79), at: UnitPoint(x: 0.08, y: 0.10), strength: dark ? 0.10 : 0.38)
            glow(Color(red: 1.00, green: 0.84, blue: 0.60), at: UnitPoint(x: 0.92, y: 0.04), strength: dark ? 0.06 : 0.32)
            glow(Color(red: 0.56, green: 0.84, blue: 0.78), at: UnitPoint(x: 0.74, y: 0.98), strength: dark ? 0.10 : 0.34)
            glow(Color(red: 0.73, green: 0.65, blue: 0.95), at: UnitPoint(x: 0.22, y: 0.92), strength: dark ? 0.14 : 0.34)
            glow(Color(red: 0.80, green: 0.89, blue: 0.96), at: UnitPoint(x: 0.55, y: 0.40), strength: dark ? 0.06 : 0.45) // the tail
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, at center: UnitPoint, strength: Double) -> some View {
        GeometryReader { geo in
            let radius = max(geo.size.width, geo.size.height) * 0.55
            RadialGradient(colors: [color.opacity(strength), color.opacity(0)], center: center, startRadius: 0, endRadius: radius)
        }
    }
}
