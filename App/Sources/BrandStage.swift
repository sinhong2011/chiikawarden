import SwiftUI

/// The login screen's brand moment, built from the app icon: a big vault door whose handle turns a
/// quarter now and then, on brand blue, with live chips around it. Follows light/dark like the icon.
struct BrandStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let dark = scheme == .dark
            GeometryReader { geo in
                let size = geo.size
                let door = min(size.width * 0.66, size.height * 0.48, 340)
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.40)
                ZStack {
                    StageBackground(dark: dark, center: center, door: door)
                    VaultDoor(handle: Self.handleAngle(t), dark: dark)
                        .frame(width: door, height: door)
                        .shadow(color: .black.opacity(dark ? 0.45 : 0.22), radius: 30, y: 18)
                        .position(center)

                    Chip(dark: dark) { CodeChip(date: context.date, dark: dark) }
                        .position(x: size.width * 0.70, y: center.y - door * 0.62 + 4 * sin(t * 0.9))
                    Chip(dark: dark) {
                        Label("Touch ID", systemImage: "touchid")
                    }
                    .position(x: size.width * 0.17, y: center.y + door * 0.30 + 5 * sin(t * 0.7 + 1))
                    Chip(dark: dark) {
                        Label("Passkey saved", systemImage: "person.badge.key.fill")
                    }
                    .position(x: size.width * 0.79, y: center.y + door * 0.60 + 4 * sin(t * 0.8 + 2))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Everything you guard,\none keystroke away.")
                            .font(.system(size: 26, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundStyle(.white)
                        Text("Passwords, passkeys, codes and SSH keys — native on your Mac.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(36)
                }
            }
        }
    }

    /// Rests, then turns a quarter with a small overshoot every 6 s — the door being opened, over and over.
    static func handleAngle(_ t: TimeInterval) -> Angle {
        let period = 6.0, turn = 1.1
        let cycle = (t / period).rounded(.down), phase = t - cycle * period
        let x = min(phase / turn, 1)
        let eased = 1 + 2.2 * pow(x - 1, 3) + 1.2 * pow(x - 1, 2)
        return .degrees((cycle + eased) * 90)
    }
}

/// Brand blue (or the icon's night navy) with faint concentric rings around the door.
private struct StageBackground: View {
    let dark: Bool
    let center: CGPoint
    let door: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: dark ? [Color(red: 0.10, green: 0.16, blue: 0.40), Color(red: 0.02, green: 0.04, blue: 0.13)]
                                        : [Color(red: 0.30, green: 0.48, blue: 1.0), Color(red: 0.11, green: 0.23, blue: 0.71)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(dark ? 0.08 : 0.20), .clear], center: .top, startRadius: 0, endRadius: 520)
            Canvas { ctx, _ in
                for k in 1...7 {
                    let r = door * (0.5 + 0.17 * CGFloat(k))
                    let ring = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                    ctx.stroke(ring, with: .color(.white.opacity(0.085 - 0.009 * Double(k))), lineWidth: 1)
                }
            }
        }
    }
}

/// The app icon's door: bolted rim, groove, and a ring handle with crossed spokes.
struct VaultDoor: View {
    var handle: Angle
    var dark: Bool

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func circle(_ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
            }
            func dot(_ p: CGPoint, _ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
            }
            let doorTop = dark ? Color(red: 0.23, green: 0.27, blue: 0.44) : .white
            let doorBottom = dark ? Color(red: 0.12, green: 0.15, blue: 0.28) : Color(red: 0.85, green: 0.89, blue: 0.98)
            let detail = dark ? Color(red: 0.56, green: 0.69, blue: 1) : Color(red: 0.14, green: 0.28, blue: 0.82)

            ctx.fill(circle(r), with: .linearGradient(Gradient(colors: [doorTop, doorBottom]),
                                                      startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
            ctx.stroke(circle(r * 0.985), with: .color(.black.opacity(dark ? 0.3 : 0.10)), lineWidth: r * 0.03)
            ctx.stroke(circle(r * 0.76), with: .color(detail.opacity(0.16)), lineWidth: r * 0.028)
            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi - .pi / 2
                ctx.fill(dot(CGPoint(x: c.x + cos(a) * r * 0.875, y: c.y + sin(a) * r * 0.875), r * 0.032),
                         with: .color(detail.opacity(0.26)))
            }

            // Handle
            let blue = GraphicsContext.Shading.linearGradient(
                Gradient(colors: dark ? [Color(red: 0.53, green: 0.67, blue: 1), Color(red: 0.29, green: 0.45, blue: 0.94)]
                                      : [Color(red: 0.36, green: 0.53, blue: 1), Color(red: 0.12, green: 0.25, blue: 0.75)]),
                startPoint: CGPoint(x: c.x, y: c.y - r * 0.6), endPoint: CGPoint(x: c.x, y: c.y + r * 0.6))
            ctx.stroke(circle(r * 0.436), with: blue, lineWidth: r * 0.11)
            let reach = r * 0.57
            var spokes = Path()
            for k in 0..<2 {
                let a = (Angle.degrees(45 + Double(k) * 90) + handle).radians
                spokes.move(to: CGPoint(x: c.x + cos(a) * reach, y: c.y + sin(a) * reach))
                spokes.addLine(to: CGPoint(x: c.x - cos(a) * reach, y: c.y - sin(a) * reach))
            }
            ctx.stroke(spokes, with: blue, style: StrokeStyle(lineWidth: r * 0.128, lineCap: .round))
            for k in 0..<4 {
                let a = (Angle.degrees(45 + Double(k) * 90) + handle).radians
                ctx.fill(dot(CGPoint(x: c.x + cos(a) * reach, y: c.y + sin(a) * reach), r * 0.105), with: blue)
            }
            ctx.fill(circle(r * 0.267), with: blue)
            ctx.fill(circle(r * 0.105), with: .color(dark ? Color(red: 0.12, green: 0.15, blue: 0.28) : .white))
        }
        .accessibilityHidden(true)
    }
}

/// Solid capsule floating over the stage: white on blue in light, navy in dark.
private struct Chip<Content: View>: View {
    var dark: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(dark ? .white : Color(red: 0.07, green: 0.13, blue: 0.36))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(dark ? Color(red: 0.13, green: 0.17, blue: 0.33) : .white, in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(dark ? 0.12 : 0)))
            .shadow(color: .black.opacity(dark ? 0.35 : 0.16), radius: 12, y: 6)
            .fixedSize()
    }
}

/// A demo one-time code that really counts down: the ring drains smoothly, clockwise from 12 o'clock.
private struct CodeChip: View {
    let date: Date
    var dark: Bool

    var body: some View {
        let period = 30.0
        let remaining = 1 - date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
        let accent = dark ? Color(red: 0.55, green: 0.69, blue: 1) : Color(red: 0.23, green: 0.39, blue: 0.91)
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(accent.opacity(0.22), lineWidth: 2)
                // Trimming from the start makes the leading edge sweep clockwise as time runs out.
                Circle().trim(from: 1 - remaining, to: 1)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
            Text(verbatim: "GitHub").opacity(0.7)
            Text(verbatim: "284 913").font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
    }
}

/// Wordmark for the login and unlock forms: the vault handle as a crisp vector glyph plus the name.
/// Drawn rather than taken from the app icon, so it is sharp at any size and always matches the brand.
struct BrandMark: View {
    var body: some View {
        HStack(spacing: 9) {
            HandleGlyph()
                .frame(width: 22, height: 22)
            Text(verbatim: "Chiikawarden")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "Chiikawarden"))
    }
}

/// The icon's handle on its own: ring, crossed spokes with knobs, hub with a punched centre.
struct HandleGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func disc(_ p: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
            let blue = GraphicsContext.Shading.color(.brand)
            ctx.stroke(disc(c, s * 0.27), with: blue, lineWidth: s * 0.10)
            let reach = s * 0.38
            var spokes = Path()
            for a in [45.0, 135.0] {
                let r = Angle.degrees(a).radians
                spokes.move(to: CGPoint(x: c.x + cos(r) * reach, y: c.y + sin(r) * reach))
                spokes.addLine(to: CGPoint(x: c.x - cos(r) * reach, y: c.y - sin(r) * reach))
            }
            ctx.stroke(spokes, with: blue, style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
            for a in [45.0, 135.0, 225.0, 315.0] {
                let r = Angle.degrees(a).radians
                ctx.fill(disc(CGPoint(x: c.x + cos(r) * reach, y: c.y + sin(r) * reach), s * 0.10), with: blue)
            }
            ctx.fill(disc(c, s * 0.17), with: blue)
            ctx.blendMode = .clear
            ctx.fill(disc(c, s * 0.065), with: .color(.black))
        }
        .accessibilityHidden(true)
    }
}
