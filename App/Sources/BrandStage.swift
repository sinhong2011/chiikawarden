import SwiftUI

/// The login screen's brand moment: a slowly turning vault dial with live "glass" chips
/// floating around it. Always dark, in both appearances, like a stage.
struct BrandStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let size = geo.size
                let dial = min(size.width * 0.86, 380)
                ZStack {
                    background
                    VaultDial(rotation: .degrees(t * 3), glow: 0.75 + 0.25 * sin(t * 1.4))
                        .frame(width: dial, height: dial)
                        .position(x: size.width * 0.5, y: size.height * 0.40)

                    Chip { CodeChip(date: context.date) }
                        .position(x: size.width * 0.70, y: size.height * 0.13 + 5 * sin(t * 0.9))
                    Chip {
                        Label("Touch ID", systemImage: "touchid")
                    }
                    .position(x: size.width * 0.20, y: size.height * 0.50 + 6 * sin(t * 0.7 + 1))
                    Chip {
                        Label("Passkey saved", systemImage: "person.badge.key.fill")
                    }
                    .position(x: size.width * 0.76, y: size.height * 0.64 + 5 * sin(t * 0.8 + 2))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Everything you guard,\none keystroke away.")
                            .font(.system(size: 26, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundStyle(.white)
                        Text("Passwords, passkeys, codes and SSH keys — native on your Mac.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(36)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.08, blue: 0.20), Color(red: 0.02, green: 0.03, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.24, green: 0.38, blue: 0.95).opacity(0.35), .clear],
                           center: UnitPoint(x: 0.5, y: 0.40), startRadius: 10, endRadius: 300)
        }
    }
}

/// Vector vault dial: bezel, minor/major ticks, glass disc and a faceted sapphire.
struct VaultDial: View {
    var rotation: Angle
    var glow: Double

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func circle(_ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
            }

            // Bezel
            ctx.stroke(circle(r * 0.86), with: .linearGradient(
                Gradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.25)]),
                startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)), lineWidth: 2)

            // Ticks, rotating slowly
            for i in 0..<60 {
                let major = i % 5 == 0
                let a = Angle.degrees(Double(i) * 6) + rotation
                let outer = r * 0.80, inner = r * (major ? 0.72 : 0.76)
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a.radians) * inner, y: c.y + sin(a.radians) * inner))
                p.addLine(to: CGPoint(x: c.x + cos(a.radians) * outer, y: c.y + sin(a.radians) * outer))
                ctx.stroke(p, with: .color(.white.opacity(major ? 0.7 : 0.22)),
                           style: StrokeStyle(lineWidth: major ? 2.4 : 1.2, lineCap: .round))
            }

            // Glass disc
            let disc = circle(r * 0.56)
            ctx.fill(disc, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.16), .white.opacity(0.03)]),
                startPoint: CGPoint(x: c.x, y: c.y - r * 0.56), endPoint: CGPoint(x: c.x, y: c.y + r * 0.56)))
            ctx.stroke(disc, with: .color(.white.opacity(0.28)), lineWidth: 1)

            // Sapphire glow
            ctx.fill(circle(r * 0.40), with: .radialGradient(
                Gradient(colors: [Color(red: 0.42, green: 0.58, blue: 1).opacity(0.55 * glow), .clear]),
                center: c, startRadius: 0, endRadius: r * 0.40))

            // Faceted sapphire (octagon)
            let g = r * 0.17
            func octagon(_ radius: CGFloat) -> [CGPoint] {
                (0..<8).map { k in
                    let a = Double(k) * .pi / 4 - .pi / 2
                    return CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
                }
            }
            let outerPts = octagon(g), innerPts = octagon(g * 0.52)
            var gem = Path(); gem.addLines(outerPts); gem.closeSubpath()
            ctx.fill(gem, with: .linearGradient(
                Gradient(colors: [Color(red: 0.80, green: 0.87, blue: 1), Color(red: 0.29, green: 0.45, blue: 0.95)]),
                startPoint: CGPoint(x: c.x, y: c.y - g), endPoint: CGPoint(x: c.x, y: c.y + g)))
            var table = Path(); table.addLines(innerPts); table.closeSubpath()
            ctx.fill(table, with: .color(.white.opacity(0.18)))
            ctx.stroke(table, with: .color(.white.opacity(0.45)), lineWidth: 1)
            var facets = Path()
            for k in 0..<8 { facets.move(to: outerPts[k]); facets.addLine(to: innerPts[k]) }
            ctx.stroke(facets, with: .color(.white.opacity(0.35)), lineWidth: 1)
        }
    }
}

/// Small glass capsule floating over the stage.
private struct Chip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.11, green: 0.14, blue: 0.30).opacity(0.92), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            .fixedSize()
    }
}

/// A demo one-time code that really counts down.
private struct CodeChip: View {
    let date: Date

    var body: some View {
        let left = 30 - Int(date.timeIntervalSince1970) % 30
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 2)
                Circle().trim(from: 0, to: Double(left) / 30)
                    .stroke(Color(red: 0.55, green: 0.69, blue: 1), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
            Text(verbatim: "GitHub").foregroundStyle(.white.opacity(0.7))
            Text(verbatim: "284 913").font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
    }
}
