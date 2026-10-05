import SwiftUI

/// The login and unlock screens' brand moment: everything the vault keeps, circling slowly around the
/// vault mark. Light and airy in light mode, deep navy in dark mode.
struct BrandStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// What circles: monochrome glyphs for the kinds of things Chiikawarden keeps.
    private static let outer = ["key.fill", "person.badge.key.fill", "terminal.fill", "creditcard.fill"]
    private static let inner = ["clock.badge.checkmark.fill", "envelope.fill", "note.text"]

    var body: some View {
        let palette = StagePalette(dark: scheme == .dark)
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let size = geo.size
                let d = min(size.width * 0.84, size.height * 0.62, 440)
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.44)
                ZStack {
                    // Fades out on the right so the stage melts into the window backdrop (no hard seam).
                    palette.background
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72),
                                                     .init(color: .clear, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))

                    // Orbits
                    ForEach([0.5, 0.33, 0.19], id: \.self) { f in
                        Circle()
                            .strokeBorder(palette.orbit, lineWidth: 1)
                            .frame(width: d * f * 2, height: d * f * 2)
                            .position(center)
                    }

                    // Travellers: outer clockwise, inner counter-clockwise, glyphs stay upright.
                    ForEach(Array(Self.outer.enumerated()), id: \.offset) { i, symbol in
                        Traveller(symbol: symbol, size: d * 0.115, palette: palette)
                            .position(Self.point(center, radius: d * 0.5,
                                                 angle: Double(i) / Double(Self.outer.count) * 360 - 90 + t * 4))
                    }
                    ForEach(Array(Self.inner.enumerated()), id: \.offset) { i, symbol in
                        Traveller(symbol: symbol, size: d * 0.092, palette: palette)
                            .position(Self.point(center, radius: d * 0.33,
                                                 angle: Double(i) / Double(Self.inner.count) * 360 + 30 - t * 6))
                    }

                    VaultMark(palette: palette)
                        .frame(width: d * 0.24, height: d * 0.24)
                        .scaleEffect(1 + 0.015 * sin(t * 1.3))
                        .shadow(color: palette.brand.opacity(0.35), radius: d * 0.05, y: d * 0.015)
                        .position(center)

                    HStack(spacing: 9) {
                        VaultMark(palette: palette).frame(width: 22, height: 22)
                        Text(verbatim: "Chiikawarden")
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(palette.ink)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(verbatim: "Chiikawarden"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 36)
                    .padding(.top, 56) // clear of the window buttons

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Every login,\nin one quiet orbit.")
                            .font(.system(size: 26, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundStyle(palette.ink)
                        Text("Passwords, passkeys, codes and SSH keys — native on your Mac.")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.ink.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(36)
                }
            }
        }
    }

    static func point(_ c: CGPoint, radius: CGFloat, angle degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
    }
}

struct StagePalette {
    let dark: Bool
    var brand: Color { dark ? Color(red: 0.28, green: 0.63, blue: 0.88) : Color(red: 0.14, green: 0.44, blue: 0.66) }
    var ink: Color { dark ? .white : Color(red: 0.05, green: 0.16, blue: 0.27) }
    var orbit: Color { dark ? .white.opacity(0.10) : Color(red: 0.14, green: 0.44, blue: 0.66).opacity(0.16) }
    var token: Color { dark ? Color(red: 0.12, green: 0.16, blue: 0.31) : .white }
    var tokenEdge: Color { dark ? .white.opacity(0.10) : Color(red: 0.14, green: 0.44, blue: 0.66).opacity(0.14) }

    var background: some View {
        ZStack {
            LinearGradient(colors: dark ? [Color(red: 0.05, green: 0.11, blue: 0.17), Color(red: 0.02, green: 0.05, blue: 0.09)]
                                        : [Color(red: 0.95, green: 0.98, blue: 1), Color(red: 0.80, green: 0.89, blue: 0.96)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [brand.opacity(dark ? 0.22 : 0.12), .clear],
                           center: UnitPoint(x: 0.5, y: 0.44), startRadius: 0, endRadius: 320)
        }
    }
}

/// A white (navy in dark mode) disc carrying one monochrome glyph.
private struct Traveller: View {
    let symbol: String
    let size: CGFloat
    let palette: StagePalette

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.40, weight: .medium))
            .foregroundStyle(palette.brand)
            .frame(width: size, height: size)
            .background(palette.token, in: .circle)
            .overlay(Circle().strokeBorder(palette.tokenEdge, lineWidth: 1))
            .shadow(color: .black.opacity(palette.dark ? 0.35 : 0.08), radius: size * 0.18, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

/// The vault mark: a brand-blue disc with the icon's handle in white (ring, crossed spokes with knobs, hub).
struct VaultMark: View {
    let palette: StagePalette

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func disc(_ p: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
            ctx.fill(disc(c, s / 2), with: .color(palette.brand))
            let white = GraphicsContext.Shading.color(.white)
            ctx.stroke(disc(c, s * 0.19), with: white, lineWidth: s * 0.065)
            let reach = s * 0.27
            var spokes = Path()
            for a in [45.0, 135.0] {
                let r = a * .pi / 180
                spokes.move(to: CGPoint(x: c.x + cos(r) * reach, y: c.y + sin(r) * reach))
                spokes.addLine(to: CGPoint(x: c.x - cos(r) * reach, y: c.y - sin(r) * reach))
            }
            ctx.stroke(spokes, with: white, style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
            for a in [45.0, 135.0, 225.0, 315.0] {
                let r = a * .pi / 180
                ctx.fill(disc(CGPoint(x: c.x + cos(r) * reach, y: c.y + sin(r) * reach), s * 0.062), with: white)
            }
            ctx.fill(disc(c, s * 0.11), with: white)
            ctx.fill(disc(c, s * 0.042), with: .color(palette.brand))
        }
        .accessibilityHidden(true)
    }
}
