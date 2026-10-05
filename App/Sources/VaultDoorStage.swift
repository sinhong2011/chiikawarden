import SwiftUI

/// The lock screen's stage: a bank-vault door set in the wall. Unlocking plays the real sequence — the dial spins
/// to the combination, the wheel turns, the bolts draw back with a clunk, and the heavy door swings open on its
/// hinge to the light inside. Brushed steel; the tail sky only marks the dial and the light.
struct VaultDoorStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    enum Caption { case lock, login }
    var caption: Caption = .lock
    /// Snapshots: draw one moment of the sequence instead of animating.
    var frozen: Motion?

    /// Everything that moves while the door opens.
    struct Motion {
        var dial = 0.0     // degrees
        var wheel = 0.0    // degrees
        var bolts = 0.0    // 0 thrown … 1 drawn back
        var shake = 0.0    // the clunk, -1…1
        var swing = 0.0    // 0 shut … 1 open
        var light = 0.0    // light from inside, 0…1
    }

    var body: some View {
        let dark = scheme == .dark
        GeometryReader { geo in
            let size = geo.size
            let r = min(size.width * 0.34, size.height * 0.29, 210)
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.42)

            if let frozen {
                scene(frozen, size: size, r: r, center: center, dark: dark)
            } else {
                KeyframeAnimator(initialValue: Motion(), trigger: model.unlockOpening) { m in
                    scene(m, size: size, r: r, center: center, dark: dark)
                } keyframes: { _ in Self.sequence }
            }
        }
    }

    /// ~1.5 s, matching AppModel's hand-off to the vault.
    @KeyframesBuilder<Motion> static var sequence: some Keyframes<Motion> {
        KeyframeTrack(\.dial) {
            CubicKeyframe(-250, duration: 0.32)
            SpringKeyframe(-216, duration: 0.18, spring: .snappy)
        }
        KeyframeTrack(\.wheel) {
            LinearKeyframe(0, duration: 0.3)
            CubicKeyframe(160, duration: 0.42)
            SpringKeyframe(150, duration: 0.14, spring: .bouncy)
        }
        KeyframeTrack(\.bolts) {
            LinearKeyframe(0, duration: 0.66)
            CubicKeyframe(1, duration: 0.2)
        }
        KeyframeTrack(\.shake) {
            LinearKeyframe(0, duration: 0.86)
            CubicKeyframe(1, duration: 0.04)
            CubicKeyframe(-0.6, duration: 0.05)
            CubicKeyframe(0, duration: 0.07)
        }
        KeyframeTrack(\.swing) {
            LinearKeyframe(0, duration: 0.95)
            CubicKeyframe(0.08, duration: 0.12) // the heavy door breaks free…
            CubicKeyframe(1, duration: 0.5)     // …then swings
        }
        KeyframeTrack(\.light) {
            LinearKeyframe(0, duration: 0.98)
            CubicKeyframe(0.35, duration: 0.2)
            CubicKeyframe(1, duration: 0.34)
        }
    }

    private func scene(_ m: Motion, size: CGSize, r: CGFloat, center: CGPoint, dark: Bool) -> some View {
                ZStack {
                    StagePalette(dark: dark).background
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72),
                                                     .init(color: .clear, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))

                    // Wall opening behind the door: dark, with the light inside.
                    VaultInterior(radius: r, light: m.light, dark: dark)
                        .position(center)

                    // The door's thickness: a steel slab edge, seen as the door turns.
                    Circle()
                        .fill(LinearGradient(colors: dark ? [Color(red: 0.22, green: 0.25, blue: 0.29), Color(red: 0.08, green: 0.09, blue: 0.11)]
                                                          : [Color(red: 0.62, green: 0.67, blue: 0.73), Color(red: 0.38, green: 0.43, blue: 0.49)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: r * 2, height: r * 2)
                        .frame(width: r * 2.3, height: r * 2.3)
                        .rotation3DEffect(.degrees(-104 * m.swing), axis: (x: 0, y: 1, z: 0),
                                          anchor: UnitPoint(x: 0.5 - 1 / 2.3, y: 0.5), anchorZ: -r * 0.22, perspective: 0.45)
                        .opacity(m.swing > 0.01 ? 1 : 0)
                        .offset(x: m.shake * 1.6, y: abs(m.shake) * 0.8)
                        .position(center)
                        .zIndex(m.swing > 0.01 ? 3 : 1)

                    // The door, hinged on its left edge; it swings out toward the viewer (in front of the frame).
                    VaultDoor(radius: r, dial: m.dial, wheel: m.wheel, bolts: m.bolts, dark: dark)
                        .frame(width: r * 2.3, height: r * 2.3)
                        .overlay(Circle().fill(.black.opacity(0.45 * m.swing)).frame(width: r * 2, height: r * 2)) // turns from the light
                        .rotation3DEffect(.degrees(-104 * m.swing), axis: (x: 0, y: 1, z: 0),
                                          anchor: UnitPoint(x: 0.5 - 1 / 2.3, y: 0.5), perspective: 0.45)
                        .shadow(color: .black.opacity((dark ? 0.55 : 0.22) + 0.2 * m.swing), radius: r * 0.12, x: r * 0.05 * (1 + m.swing * 3), y: r * 0.06)
                        .offset(x: m.shake * 1.6, y: abs(m.shake) * 0.8)
                        .position(center)
                        .zIndex(m.swing > 0.01 ? 4 : 1)

                    VaultFrame(radius: r, dark: dark)
                        .frame(width: r * 2.6, height: r * 2.6)
                        .position(center)
                        .allowsHitTesting(false)
                        .zIndex(2)

                    // At the end the light fills the stage and hands over to the vault.
                    RadialGradient(colors: [Color.white.opacity(0.95 * m.light * m.light), Color.brandFill.opacity(0.5 * m.light), .clear],
                                   center: UnitPoint(x: center.x / size.width, y: center.y / size.height),
                                   startRadius: 0, endRadius: r * (1 + 2.6 * m.light))
                        .allowsHitTesting(false)
                        .zIndex(5)

                    caption(dark: dark)
                        .opacity(1 - m.light)
                        .zIndex(6)
                }
    }

    private func caption(dark: Bool) -> some View {
        let ink = StagePalette(dark: dark).ink
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Chiikawarden")
                .font(.system(size: 20, weight: .semibold)).tracking(-0.3)
                .foregroundStyle(StagePalette(dark: dark).brand)
                .padding(.bottom, 4)
            switch caption {
            case .lock:
                Text("Sealed tight.\nOpens only for you.")
                    .font(.system(size: 26, weight: .semibold)).tracking(-0.4)
                    .foregroundStyle(ink)
                Text("Your vault is encrypted on this Mac until you unlock it.")
                    .font(.system(size: 13)).foregroundStyle(ink.opacity(0.62))
            case .login:
                Text("Every login,\nbehind one door.")
                    .font(.system(size: 26, weight: .semibold)).tracking(-0.4)
                    .foregroundStyle(ink)
                Text("Passwords, passkeys, codes and SSH keys — native on your Mac.")
                    .font(.system(size: 13)).foregroundStyle(ink.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(36)
    }
}

// MARK: - Parts

/// Stage colours: airy sky in light mode, deep navy in dark mode.
struct StagePalette {
    let dark: Bool
    var brand: Color { dark ? Color.brandFill : Color(red: 0.06, green: 0.45, blue: 0.70) }
    var ink: Color { dark ? .white : Color(red: 0.05, green: 0.16, blue: 0.27) }
    var orbit: Color { dark ? .white.opacity(0.10) : Color.brandFill.opacity(0.45) }
    var token: Color { dark ? Color(red: 0.12, green: 0.16, blue: 0.31) : .white }
    var tokenEdge: Color { dark ? .white.opacity(0.10) : Color.brandFill.opacity(0.5) }

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


private struct Steel {
    let dark: Bool
    var face: [Color] {
        dark ? [Color(red: 0.36, green: 0.40, blue: 0.46), Color(red: 0.18, green: 0.21, blue: 0.25)]
             : [Color(red: 0.95, green: 0.96, blue: 0.98), Color(red: 0.72, green: 0.77, blue: 0.82)]
    }
    var rim: [Color] {
        dark ? [Color(red: 0.30, green: 0.34, blue: 0.39), Color(red: 0.12, green: 0.14, blue: 0.17)]
             : [Color(red: 0.86, green: 0.89, blue: 0.92), Color(red: 0.58, green: 0.63, blue: 0.69)]
    }
    var groove: Color { dark ? .black.opacity(0.45) : Color(red: 0.35, green: 0.42, blue: 0.50).opacity(0.35) }
    var highlight: Color { .white.opacity(dark ? 0.12 : 0.7) }
    var bolt: [Color] {
        dark ? [Color(red: 0.62, green: 0.66, blue: 0.71), Color(red: 0.32, green: 0.35, blue: 0.40)]
             : [Color(red: 0.97, green: 0.98, blue: 0.99), Color(red: 0.66, green: 0.71, blue: 0.77)]
    }
    var handle: [Color] {
        dark ? [Color(red: 0.80, green: 0.83, blue: 0.87), Color(red: 0.46, green: 0.50, blue: 0.56)]
             : [Color(red: 0.99, green: 0.99, blue: 1.0), Color(red: 0.62, green: 0.67, blue: 0.73)]
    }
}

/// The round door: machined face, locking bolts, the wheel and the combination dial.
private struct VaultDoor: View {
    let radius: CGFloat
    let dial: Double
    let wheel: Double
    let bolts: Double
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            let steel = Steel(dark: dark)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = radius
            func circle(_ radius: CGFloat, at p: CGPoint? = nil) -> Path {
                let p = p ?? c
                return Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
            }
            func linear(_ colors: [Color], _ radius: CGFloat) -> GraphicsContext.Shading {
                .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: c.x - radius, y: c.y - radius),
                                endPoint: CGPoint(x: c.x + radius, y: c.y + radius))
            }

            // Locking bolts: thrown out into the frame; drawn back into the door when unlocking.
            let throw_ = r * 0.16 * (1 - bolts)
            for i in 0..<16 {
                let a = Double(i) / 16 * 2 * .pi
                var bolt = ctx
                bolt.translateBy(x: c.x, y: c.y)
                bolt.rotate(by: .radians(a))
                let rect = CGRect(x: r * 0.84 + throw_, y: -r * 0.035, width: r * 0.2, height: r * 0.07)
                bolt.fill(Path(roundedRect: rect, cornerRadius: r * 0.02), with: .linearGradient(
                    Gradient(colors: steel.bolt), startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
            }

            // Door body and its stepped rim.
            ctx.fill(circle(r), with: linear(steel.rim, r))
            ctx.fill(circle(r * 0.9), with: linear(steel.face, r))
            ctx.stroke(circle(r * 0.9), with: .color(steel.highlight), lineWidth: 1)
            for f in [0.78, 0.6] {
                ctx.stroke(circle(r * f), with: .color(steel.groove), lineWidth: 1.2)
                ctx.stroke(circle(r * f - 1.2), with: .color(steel.highlight), lineWidth: 0.8)
            }
            // Rivets around the rim.
            for i in 0..<24 {
                let a = Double(i) / 24 * 2 * .pi + .pi / 24
                let p = CGPoint(x: c.x + cos(a) * r * 0.95, y: c.y + sin(a) * r * 0.95)
                ctx.fill(circle(r * 0.016, at: p), with: .color(steel.groove))
                ctx.fill(circle(r * 0.011, at: CGPoint(x: p.x - 0.5, y: p.y - 0.5)), with: .color(steel.highlight))
            }

            // The wheel: three spokes with knobs, turning together.
            var w = ctx
            w.translateBy(x: c.x, y: c.y)
            w.rotate(by: .degrees(wheel))
            let handle = GraphicsContext.Shading.linearGradient(Gradient(colors: steel.handle),
                                                                startPoint: CGPoint(x: -r * 0.5, y: -r * 0.5), endPoint: CGPoint(x: r * 0.5, y: r * 0.5))
            for k in 0..<3 {
                let a = Double(k) / 3 * 2 * .pi - .pi / 2
                let end = CGPoint(x: cos(a) * r * 0.5, y: sin(a) * r * 0.5)
                var spoke = Path()
                spoke.move(to: .zero)
                spoke.addLine(to: end)
                w.stroke(spoke, with: .color(.black.opacity(dark ? 0.4 : 0.15)), style: StrokeStyle(lineWidth: r * 0.075, lineCap: .round))
                w.stroke(spoke, with: handle, style: StrokeStyle(lineWidth: r * 0.06, lineCap: .round))
                let knob = Path(ellipseIn: CGRect(x: end.x - r * 0.07, y: end.y - r * 0.07, width: r * 0.14, height: r * 0.14))
                w.fill(knob, with: handle)
                w.stroke(knob, with: .color(.black.opacity(dark ? 0.35 : 0.12)), lineWidth: 1)
            }
            w.stroke(Path(ellipseIn: CGRect(x: -r * 0.36, y: -r * 0.36, width: r * 0.72, height: r * 0.72)),
                     with: handle, lineWidth: r * 0.035)

            // Combination dial at the hub: numbered ticks turning; a fixed sky marker at the top.
            ctx.fill(circle(r * 0.22), with: linear(steel.rim, r * 0.22))
            var d = ctx
            d.translateBy(x: c.x, y: c.y)
            d.rotate(by: .degrees(dial))
            for i in 0..<40 {
                let a = Double(i) / 40 * 2 * .pi
                let long = i % 5 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: cos(a) * r * (long ? 0.15 : 0.17), y: sin(a) * r * (long ? 0.15 : 0.17)))
                tick.addLine(to: CGPoint(x: cos(a) * r * 0.2, y: sin(a) * r * 0.2))
                d.stroke(tick, with: .color(dark ? .white.opacity(0.55) : .black.opacity(0.45)), lineWidth: long ? 1.4 : 0.8)
            }
            ctx.fill(circle(r * 0.1), with: linear(steel.handle, r * 0.1))
            var marker = Path()
            marker.move(to: CGPoint(x: c.x, y: c.y - r * 0.205))
            marker.addLine(to: CGPoint(x: c.x - r * 0.025, y: c.y - r * 0.25))
            marker.addLine(to: CGPoint(x: c.x + r * 0.025, y: c.y - r * 0.25))
            marker.closeSubpath()
            ctx.fill(marker, with: .color(.brandFill))
        }
        .accessibilityHidden(true)
    }
}

/// The thick ring the door sits in, with its two hinge blocks on the left.
private struct VaultFrame: View {
    let radius: CGFloat
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            let steel = Steel(dark: dark)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = radius
            var ring = Path(ellipseIn: CGRect(x: c.x - r * 1.22, y: c.y - r * 1.22, width: r * 2.44, height: r * 2.44))
            ring.addPath(Path(ellipseIn: CGRect(x: c.x - r * 1.04, y: c.y - r * 1.04, width: r * 2.08, height: r * 2.08)))
            ctx.fill(ring, with: .linearGradient(Gradient(colors: steel.rim), startPoint: CGPoint(x: c.x - r, y: c.y - r * 1.2),
                                                 endPoint: CGPoint(x: c.x + r, y: c.y + r * 1.2)), style: FillStyle(eoFill: true))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 1.04, y: c.y - r * 1.04, width: r * 2.08, height: r * 2.08)),
                       with: .color(.black.opacity(dark ? 0.5 : 0.18)), lineWidth: 2)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 1.22, y: c.y - r * 1.22, width: r * 2.44, height: r * 2.44)),
                       with: .color(steel.highlight), lineWidth: 1)
            for y in [-0.55, 0.55] {
                let rect = CGRect(x: c.x - r * 1.3, y: c.y + r * y - r * 0.13, width: r * 0.3, height: r * 0.26)
                ctx.fill(Path(roundedRect: rect, cornerRadius: r * 0.04), with: .linearGradient(
                    Gradient(colors: steel.bolt), startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: r * 0.04), with: .color(.black.opacity(dark ? 0.4 : 0.15)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

/// What the door reveals: the dark opening and the light inside.
private struct VaultInterior: View {
    let radius: CGFloat
    let light: Double
    let dark: Bool

    var body: some View {
        ZStack {
            Circle().fill(dark ? Color(red: 0.03, green: 0.05, blue: 0.08) : Color(red: 0.14, green: 0.19, blue: 0.25))
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.9 * light), Color.brandFill.opacity(0.8 * light), .clear],
                                         center: .center, startRadius: 0, endRadius: radius * 1.05))
        }
        .frame(width: radius * 2.08, height: radius * 2.08)
        .accessibilityHidden(true)
    }
}
