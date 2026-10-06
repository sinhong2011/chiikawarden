import SwiftUI

/// A frozen moment of the lock screen, for snapshots: `time` seconds after the door appeared, `opened` seconds into
/// the unlock sequence (nil = still locked).
struct VaultDoorFrozen {
    var time: Double
    var opened: Double?
    /// Seconds into the closing sequence (a lock the user asked for).
    var closed: Double? = nil
    var typed = 0
    var busy = false
    var alert = 0.0
}

extension EnvironmentValues {
    @Entry var vaultDoorFrozen: VaultDoorFrozen?
}

/// The lock screen's door: a round, faintly enchanted vault door. Light from inside the vault leaks through its seams;
/// every typed character lights a pin and turns the tumblers. Unlocking takes the door apart like a transforming
/// machine; locking assembles it again. No shaking anywhere.
struct VaultDoorStage: View {
    let radius: CGFloat
    let center: CGPoint
    let typed: Int
    /// Notches the tumblers have turned: one per typed character, but a paste or a clear takes the short way round.
    let turns: Int
    let busy: Bool
    let errorAt: Date?
    let openedAt: Date?
    let closedAt: Date?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.vaultDoorFrozen) private var frozen
    @Environment(\.gatePassing) private var gatePassing
    @AppStorage(Pref.lockAnimations) private var animates = true
    @State private var start = Date()

    var body: some View {
        Group {
            if let frozen {
                art(time: frozen.time, opened: frozen.opened, closed: frozen.closed, alert: frozen.alert, typed: frozen.typed,
                    turns: frozen.typed, busy: frozen.busy)
            } else {
                let still = reduceMotion || !animates
                // Inside the gate's halves the door holds still (one frame), so the halves are cheap to move.
                TimelineView(.animation(paused: still || gatePassing)) { context in
                    let now = context.date
                    art(time: still ? 0 : now.timeIntervalSince(start),
                        opened: openedAt.map { now.timeIntervalSince($0) },
                        closed: closedAt.map { now.timeIntervalSince($0) },
                        alert: still ? 0 : errorAt.map { Self.alert(now.timeIntervalSince($0)) } ?? 0,
                        typed: typed, turns: turns, busy: busy)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// A wrong password: the light warms to red quickly, then cools back over a second and a half.
    private static func alert(_ s: Double) -> Double {
        s < 0.15 ? max(0, s / 0.15) : max(0, 1 - (s - 0.15) / 1.5)
    }

    private func art(time: Double, opened: Double?, closed: Double?, alert: Double, typed: Int, turns: Int,
                     busy: Bool) -> some View {
        VaultDoorArt(steps: Double(turns), busy: busy ? 1 : 0, time: time, opened: opened, closed: closed, alert: alert,
                     lit: typed, radius: radius, center: center, dark: scheme == .dark)
            .animation(.easeInOut(duration: 0.4), value: busy)
    }
}

// MARK: - Mechanism

/// Where every moving part is at one instant. The door is built from pieces: the hub (4 plates), the pin ring
/// (4 arcs), the tumbler (12 louvres) and the rune ring (6 segments). Unlocking takes it apart from the inside out,
/// like a transforming machine; locking assembles it from the outside in.
private struct Mechanism {
    /// Per ring (0 hub, 1 pins, 2 tumbler, 3 runes): how far it has turned to its aligned stop, 0…1.
    var align = [0.0, 0, 0, 0]
    /// Per ring: 0 assembled … 1 retracted out of sight.
    var parts = [0.0, 0, 0, 0]
    /// The pieces crack apart along their seams, 0…1.
    var latch = 0.0
    /// Bolts drawn back into the door, 0 thrown … 1 drawn.
    var bolts = 0.0
    /// Every pin lit, 0…1.
    var pins = 0.0
    /// The light inside burning brighter, 0…1.
    var light = 0.0
    /// The sealing ripple after a lock, 0…1 (0 or 1 = not showing).
    var seal = 0.0

    /// Unlocking, `e` seconds in (~0.85 s; AppModel dissolves the lock layer at 0.8 s).
    static func opening(_ e: Double) -> Mechanism {
        func seg(_ a: Double, _ b: Double) -> Double { min(1, max(0, (e - a) / (b - a))) }
        var m = Mechanism()
        for k in 0..<4 {
            m.align[k] = Ease.inOut(seg(0.02 * Double(k), 0.18 + 0.02 * Double(k)))
            // The pieces spread apart, inside out (the light stays calm: no flare or growing halo behind them).
            m.parts[k] = Ease.machine(seg(0.3 + 0.08 * Double(k), 0.62 + 0.08 * Double(k)))
        }
        m.pins = Ease.out(seg(0, 0.14))
        m.bolts = Ease.inOut(seg(0.14, 0.28))
        m.latch = Ease.inOut(seg(0.26, 0.36))
        m.light = Ease.out(seg(0.05, 0.6))
        return m
    }

    /// Locking, `e` seconds in (~1.2 s): the pieces come in from the frame and lock together, the bolts are thrown,
    /// the pins go dark, and the seal ripples out.
    static func closing(_ e: Double) -> Mechanism {
        func seg(_ a: Double, _ b: Double) -> Double { min(1, max(0, (e - a) / (b - a))) }
        var m = Mechanism()
        for k in 0..<4 {
            m.align[k] = 1
            let start = 0.02 + 0.08 * Double(3 - k)
            m.parts[k] = 1 - Ease.machine(seg(start, start + 0.32))
        }
        m.latch = 1 - Ease.inOut(seg(0.5, 0.6))
        m.bolts = 1 - Ease.inOut(seg(0.56, 0.7))
        m.pins = 1 - Ease.inOut(seg(0.66, 0.95))
        m.light = m.pins
        m.seal = seg(0.66, 1.2)
        return m
    }
}

private enum Ease {
    static func inOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    static func out(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    /// Heavy mechanical travel: eases away, glides, settles firmly (no overshoot).
    static func machine(_ x: Double) -> Double { x < 0.5 ? 8 * pow(x, 4) : 1 - pow(-2 * x + 2, 4) / 2 }
}

// MARK: - Palette

private struct RGB {
    var r, g, b: Double
    func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
    func callAsFunction(_ opacity: Double = 1) -> Color { Color(red: r, green: g, blue: b).opacity(opacity) }
}

private struct DoorPalette {
    let dark: Bool
    var backTop: Color { dark ? Color(red: 0.05, green: 0.08, blue: 0.13) : Color(red: 0.95, green: 0.97, blue: 0.99) }
    var backBottom: Color { dark ? Color(red: 0.02, green: 0.03, blue: 0.06) : Color(red: 0.83, green: 0.89, blue: 0.95) }
    var metal: [Color] {
        dark ? [Color(red: 0.30, green: 0.32, blue: 0.36), Color(red: 0.13, green: 0.14, blue: 0.17)]
             : [Color(red: 0.99, green: 0.99, blue: 1), Color(red: 0.76, green: 0.80, blue: 0.85)]
    }
    var frame: [Color] {
        dark ? [Color(red: 0.20, green: 0.21, blue: 0.24), Color(red: 0.07, green: 0.08, blue: 0.10)]
             : [Color(red: 0.90, green: 0.93, blue: 0.96), Color(red: 0.68, green: 0.75, blue: 0.82)]
    }
    var recess: [Color] {
        dark ? [Color(red: 0.03, green: 0.05, blue: 0.08), Color(red: 0.08, green: 0.11, blue: 0.16)]
             : [Color(red: 0.86, green: 0.91, blue: 0.95), Color(red: 0.97, green: 0.98, blue: 1)]
    }
    var bolt: [Color] {
        dark ? [Color(red: 0.62, green: 0.68, blue: 0.75), Color(red: 0.30, green: 0.35, blue: 0.42)]
             : [Color(red: 1, green: 1, blue: 1), Color(red: 0.70, green: 0.76, blue: 0.83)]
    }
    var edge: Color { dark ? .black.opacity(0.55) : Color(red: 0.20, green: 0.30, blue: 0.42).opacity(0.28) }
    var shine: Color { .white.opacity(dark ? 0.14 : 0.9) }
    var engrave: Color { dark ? .black.opacity(0.6) : Color(red: 0.15, green: 0.22, blue: 0.32).opacity(0.38) }
    /// The catch of light along the lower lip of an engraved line.
    var engraveLip: Color { .white.opacity(dark ? 0.10 : 0.8) }
    /// The light inside the vault: the tail sky (a deeper sky on light steel), warming to red for a wrong password.
    func glow(alert: Double) -> RGB {
        let sky = dark ? RGB(r: 0.50, g: 0.77, b: 0.94) : RGB(r: 0.18, g: 0.56, b: 0.83)
        let red = dark ? RGB(r: 1.0, g: 0.45, b: 0.45) : RGB(r: 0.88, g: 0.27, b: 0.27)
        return sky.mix(red, alert)
    }
}

// MARK: - Drawing

/// Proportions of the door, as fractions of its radius.
enum DoorGeometry {
    static let frameOuter = 1.13
    static let runes = (inner: 0.845, outer: 0.985)
    static let tumbler = (inner: 0.715, outer: 0.83)
    static let pins = (inner: 0.595, outer: 0.70)
    /// The recessed hub that holds the password field.
    static let core = 0.58
}

private struct VaultDoorArt: View, Animatable {
    var steps: Double
    var busy: Double
    let time: Double
    let opened: Double?
    let closed: Double?
    let alert: Double
    let lit: Int
    let radius: CGFloat
    let center: CGPoint
    let dark: Bool

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(steps, busy) }
        set { steps = newValue.first; busy = newValue.second }
    }

    private static let runeSymbols = ["key.fill", "person.badge.key.fill", "terminal.fill",
                                      "creditcard.fill", "envelope.fill", "note.text"]

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size: size) }
            .drawingGroup() // rendered with Metal: smooth at 120 Hz while the pieces move
    }

    private var mechanism: Mechanism {
        if let opened { return .opening(opened) }
        if let closed { return .closing(closed) }
        return Mechanism()
    }

    // Ring angles in degrees. The tumbler drifts and turns half a notch per character; the pin ring only moves when
    // typing, bringing the newest lit pin to the marker at the top. Unlocking turns each to its next aligned stop.
    private func idle(_ k: Int, at t: Double) -> Double {
        switch k {
        case 3: t * 2.2
        case 2: -t * 3.2 + steps * 15
        case 1: -steps * 30 + 30
        default: 0
        }
    }
    private static let symmetry: [Double] = [90, 30, 30, 60]
    private static let direction: [Double] = [1, -1, 1, 1]

    private func angle(_ k: Int, _ m: Mechanism) -> Double {
        guard k > 0 else { return 0 }
        guard let e = opened else { return idle(k, at: time) }
        let a0 = idle(k, at: time - e)
        let sym = Self.symmetry[k]
        let target = Self.direction[k] > 0 ? (floor(a0 / sym) + 1) * sym : (ceil(a0 / sym) - 1) * sym
        return a0 + (target - a0) * m.align[k]
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let p = DoorPalette(dark: dark)
        let m = mechanism
        let R = radius
        let glow = p.glow(alert: alert)
        let breathe = 0.5 + 0.5 * sin(time * 1.1)
        // How bright the light inside is: breathing at rest, quicker while the key is derived, blazing as it opens.
        // (Opening only lifts it a little: no flare, no spreading wave as the pieces part.)
        let inner = min(1, 0.5 + 0.12 * breathe + busy * (0.18 + 0.12 * sin(time * 5)) + 0.5 * alert + 0.15 * m.light)

        // Room: translucent, so the lock reads as a layer over the window.
        let full = Path(CGRect(origin: .zero, size: size))
        ctx.fill(full, with: .linearGradient(Gradient(colors: [p.backTop.opacity(0.86), p.backBottom.opacity(0.9)]),
                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        ctx.fill(full, with: .radialGradient(Gradient(colors: [glow(dark ? 0.16 : 0.14), glow(0)]), center: center,
                                             startRadius: 0, endRadius: R * 1.9))
        drawMotes(&ctx, glow: glow)

        var c = ctx
        c.translateBy(x: center.x, y: center.y)

        // A soft halo of light around the door.
        c.fill(circle(R * 1.4), with: .radialGradient(
            Gradient(stops: [.init(color: glow(0), location: 0), .init(color: glow(0.2), location: 0.45),
                             .init(color: glow(0), location: 1)]),
            center: .zero, startRadius: R * 1.0, endRadius: R * 1.4))

        // The light inside the vault: it shows through the seams and the tumbler's slots, then through the opening.
        let open = m.parts[0]
        c.fill(circle(1.0 * R), with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.4 * inner + 0.12 * open), glow(inner), glow(inner * 0.75)]),
            center: .zero, startRadius: 0, endRadius: R))

        // Locking bolts: thrown into the frame; drawn back into the door as it unlocks.
        let pull = R * 0.22 * m.bolts
        for i in 0..<12 {
            var b = c
            b.opacity = 1 - m.parts[3]
            b.rotate(by: .degrees(Double(i) * 30 + 15))
            let rect = CGRect(x: R * 0.9 - pull, y: -R * 0.026, width: R * 0.165, height: R * 0.052)
            let shape = Path(roundedRect: rect, cornerRadius: R * 0.018)
            b.fill(shape, with: .linearGradient(Gradient(colors: p.bolt), startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                                endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
            b.stroke(shape, with: .color(p.edge), lineWidth: 0.8)
        }

        // The pieces, inside out, so each slides out under the next; the rune segments retract into the frame.
        c.clip(to: circle(1.0 * R))
        let turn = (0..<4).map { angle($0, m) }
        pieces(c, ring: 0, m: m, p: p, count: 4, cut: 0, inner: 0, outer: DoorGeometry.core) { drawCore(&$0, p: p, glow: glow) }
        pieces(c, ring: 1, m: m, p: p, count: 4, cut: 0, inner: DoorGeometry.pins.inner, outer: DoorGeometry.pins.outer) {
            drawPins(&$0, p: p, m: m, glow: glow, turn: turn[1])
        }
        pieces(c, ring: 2, m: m, p: p, count: 12, cut: 15, inner: DoorGeometry.tumbler.inner, outer: DoorGeometry.tumbler.outer) {
            drawTumbler(&$0, p: p, glow: glow, inner: inner, turn: turn[2])
        }
        pieces(c, ring: 3, m: m, p: p, count: 6, cut: 30, inner: DoorGeometry.runes.inner, outer: DoorGeometry.runes.outer) {
            drawRunes(&$0, p: p, m: m, glow: glow, turn: turn[3])
        }

        // Seams glow onto the steel around them (while the door is whole).
        if m.latch < 1 {
            var l = c
            if dark { l.blendMode = .plusLighter }
            let a = (0.35 + 0.5 * inner) * (1 - m.latch)
            for f in [0.9925, 0.8375, 0.7075, DoorGeometry.core + 0.0075] {
                l.stroke(circle(R * f), with: .color(glow(a * (dark ? 0.12 : 0.18))), lineWidth: R * 0.034)
                l.stroke(circle(R * f), with: .color(glow(a * (dark ? 0.5 : 0.7))), lineWidth: R * 0.006)
            }
        }

        // The frame the door sits in.
        c = ctx
        c.translateBy(x: center.x, y: center.y)
        fillBand(&c, inner: 1.0 * R, outer: DoorGeometry.frameOuter * R, colors: p.frame, turn: 0)
        c.stroke(circle(DoorGeometry.frameOuter * R), with: .color(p.shine), lineWidth: 1)
        c.stroke(circle(1.1 * R), with: .color(p.engrave), lineWidth: 0.8)
        for i in 0..<24 {
            let a = (Double(i) + 0.5) / 24 * 2 * .pi
            let pt = CGPoint(x: cos(a) * R * 1.065, y: sin(a) * R * 1.065)
            c.fill(circle(R * 0.013, at: pt), with: .color(p.edge))
            c.fill(circle(R * 0.008, at: CGPoint(x: pt.x - 0.4, y: pt.y - 0.4)), with: .color(p.shine))
        }

        // Sealed: one ring of light ripples out from the frame.
        if m.seal > 0, m.seal < 1 {
            let k = Ease.out(m.seal)
            let ripple = circle(R * (DoorGeometry.frameOuter + 0.55 * k))
            c.stroke(ripple, with: .color(glow(0.18 * (1 - m.seal))), lineWidth: R * 0.07 * (1 - k * 0.6))
            c.stroke(ripple, with: .color(glow(0.9 * (1 - m.seal))), lineWidth: 1.5)
        }
    }

    // MARK: Pieces

    /// Draws ring `ring` (turned to its angle; `inner`/`outer` as fractions of the radius) as `count` pieces cut at `cut` + multiples of 360/count degrees, each
    /// moved by the mechanism. Whole and unmoved, it's drawn in one go.
    private func pieces(_ c: GraphicsContext, ring k: Int, m: Mechanism, p: DoorPalette, count: Int, cut: Double,
                        inner: CGFloat, outer: CGFloat, draw: (inout GraphicsContext) -> Void) {
        let R = radius
        var base = c
        base.rotate(by: .degrees(angle(k, m)))
        let u = m.parts[k]
        guard m.latch > 0 || u > 0 else { draw(&base); return }
        guard u < 1 else { return }
        let span = 360 / Double(count)
        for i in 0..<count {
            let mid = cut + (Double(i) + 0.5) * span
            let rad = mid * .pi / 180
            let dir = CGPoint(x: cos(rad), y: sin(rad))
            var l = base
            // Every piece first cracks a hair away from the centre…
            var push = R * 0.02 * m.latch
            // …then each ring moves its own way.
            switch k {
            case 0: // hub plates slide out diagonally, under the rings
                push += R * 0.6 * u
                l.opacity = 1 - max(0, (u - 0.5) / 0.5)
            case 1: // pin arcs turn as they slide away
                l.rotate(by: .degrees(28 * u))
                push += R * 0.36 * u
                l.opacity = 1 - max(0, (u - 0.55) / 0.45)
            case 2: // tumbler louvres turn edge-on
                push += R * 0.1 * u
                let mr = R * (inner + outer) / 2
                let pivot = CGPoint(x: dir.x * mr, y: dir.y * mr)
                l.translateBy(x: dir.x * push, y: dir.y * push)
                push = 0
                l.translateBy(x: pivot.x, y: pivot.y)
                l.rotate(by: .degrees(mid))
                l.scaleBy(x: 1, y: max(0.04, cos(u * .pi / 2)))
                l.rotate(by: .degrees(-mid))
                l.translateBy(x: -pivot.x, y: -pivot.y)
                l.opacity = 1 - max(0, (u - 0.6) / 0.4)
            default: // rune segments retract into the frame
                l.rotate(by: .degrees(-10 * u))
                push += R * 0.3 * u
            }
            l.translateBy(x: dir.x * push, y: dir.y * push)
            let shape = sector(inner == 0 ? 0 : R * inner - 1, R * outer + 1, mid - span / 2, mid + span / 2)
            // Thick steel: a soft shadow on the light behind, then the piece, then its machined cut faces.
            let lift = R * 0.014 * max(m.latch, u)
            if lift > 0 {
                var s = l
                s.translateBy(x: 0, y: lift)
                s.fill(shape, with: .color(.black.opacity(dark ? 0.35 : 0.16)))
                s.translateBy(x: 0, y: lift)
                s.fill(shape, with: .color(.black.opacity(dark ? 0.18 : 0.08)))
            }
            var piece = l
            piece.clip(to: shape)
            draw(&piece)
            let faces = max(m.latch, min(1, u * 4))
            if faces > 0 {
                l.stroke(shape, with: .linearGradient(Gradient(colors: [p.shine.opacity(faces), p.edge.opacity(faces)]),
                                                      startPoint: CGPoint(x: 0, y: -R), endPoint: CGPoint(x: 0, y: R)),
                         lineWidth: 1.2)
            }
        }
    }

    private func sector(_ r0: CGFloat, _ r1: CGFloat, _ a0: Double, _ a1: Double) -> Path {
        var path = Path()
        path.addArc(center: .zero, radius: r1, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
        if r0 > 0 {
            path.addArc(center: .zero, radius: r0, startAngle: .degrees(a1), endAngle: .degrees(a0), clockwise: true)
        } else {
            path.addLine(to: .zero)
        }
        path.closeSubpath()
        return path
    }

    // MARK: Rings (drawn already turned to their angle)

    private func drawRunes(_ r: inout GraphicsContext, p: DoorPalette, m: Mechanism, glow: RGB, turn: Double) {
        let R = radius
        fillBand(&r, inner: DoorGeometry.runes.inner * R, outer: DoorGeometry.runes.outer * R, colors: p.metal, turn: turn)
        for i in 0..<72 {
            let long = i % 6 == 3
            let t = Double(i) / 72 * 2 * .pi
            var tick = Path()
            tick.move(to: CGPoint(x: cos(t) * R * (long ? 0.935 : 0.95), y: sin(t) * R * (long ? 0.935 : 0.95)))
            tick.addLine(to: CGPoint(x: cos(t) * R * 0.97, y: sin(t) * R * 0.97))
            engrave(&r, tick, p: p, width: long ? 1.1 : 0.7)
        }
        for i in 0..<6 {
            let local = Double(i) * 60
            let shimmer = 0.5 + 0.5 * sin(time * 0.9 + Double(i) * 1.7)
            let glowAmount = max(dark ? 0.45 + 0.3 * shimmer : 0.3 + 0.25 * shimmer, m.light)

            var g = r
            g.rotate(by: .degrees(local))
            g.translateBy(x: R * 0.893, y: 0)
            g.rotate(by: .degrees(90))
            var image = g.resolve(Image(systemName: Self.runeSymbols[i]))
            let side = R * 0.082
            let scale = side / max(image.size.width, image.size.height, 1)
            let rect = CGRect(x: -image.size.width * scale / 2, y: -image.size.height * scale / 2,
                              width: image.size.width * scale, height: image.size.height * scale)
            // Inlaid: a soft pool of light around the rune, the cut, then the glowing fill.
            g.fill(circle(R * 0.075), with: .radialGradient(Gradient(colors: [glow(glowAmount * 0.45), glow(0)]),
                                                            center: .zero, startRadius: 0, endRadius: R * 0.075))
            image.shading = .color(p.engraveLip)
            g.draw(image, in: rect.offsetBy(dx: 0, dy: 0.7))
            image.shading = .color(p.engrave)
            g.draw(image, in: rect)
            image.shading = .color(glow(glowAmount * (dark ? 1 : 0.9)))
            g.draw(image, in: rect)

            // A small diamond between runes.
            var d = r
            d.rotate(by: .degrees(local + 30))
            var diamond = Path()
            let s = R * 0.012
            diamond.move(to: CGPoint(x: R * 0.893 - s, y: 0))
            diamond.addLine(to: CGPoint(x: R * 0.893, y: -s))
            diamond.addLine(to: CGPoint(x: R * 0.893 + s, y: 0))
            diamond.addLine(to: CGPoint(x: R * 0.893, y: s))
            diamond.closeSubpath()
            d.fill(diamond, with: .color(p.engrave))
        }
    }

    private func drawTumbler(_ r: inout GraphicsContext, p: DoorPalette, glow: RGB, inner: Double, turn: Double) {
        let R = radius
        fillBand(&r, inner: DoorGeometry.tumbler.inner * R, outer: DoorGeometry.tumbler.outer * R, colors: p.metal, turn: turn)
        for i in 0..<12 {
            var s = r
            s.rotate(by: .degrees(Double(i) * 30))
            // A slot through the tumbler: the vault's light shows through it.
            let slot = CGRect(x: R * 0.738, y: -R * 0.014, width: R * 0.07, height: R * 0.028)
            let path = Path(roundedRect: slot, cornerRadius: R * 0.014)
            s.fill(path, with: .color(glow(0.55 + 0.45 * inner)))
            s.fill(path, with: .color(.white.opacity(0.3 * inner)))
            // The slot's walls: shadowed on the lit side, a lip of light on the other.
            s.stroke(path, with: .color(p.edge), lineWidth: 1.2)
            s.stroke(path.offsetBy(dx: 0, dy: 0.6), with: .color(p.engraveLip.opacity(0.6)), lineWidth: 0.5)
            s.rotate(by: .degrees(15))
            s.fill(circle(R * 0.009, at: CGPoint(x: R * 0.7725, y: 0)), with: .color(p.engrave))
        }
    }

    private func drawPins(_ r: inout GraphicsContext, p: DoorPalette, m: Mechanism, glow: RGB, turn: Double) {
        let R = radius
        // While the key is derived, a light chases around the pins.
        let head = (time * 1.6).truncatingRemainder(dividingBy: 1) * 12
        fillBand(&r, inner: DoorGeometry.pins.inner * R, outer: DoorGeometry.pins.outer * R, colors: p.metal, turn: turn)
        for i in 0..<60 {
            let long = i % 5 == 0
            let t = Double(i) / 60 * 2 * .pi
            var tick = Path()
            tick.move(to: CGPoint(x: cos(t) * R * (long ? 0.665 : 0.675), y: sin(t) * R * (long ? 0.665 : 0.675)))
            tick.addLine(to: CGPoint(x: cos(t) * R * 0.688, y: sin(t) * R * 0.688))
            engrave(&r, tick, p: p, width: long ? 1 : 0.6)
        }
        for i in 0..<12 {
            // Pin i sits at the top when it's the newest lit one (the ring turns 30° per character).
            let t = (Double(i) * 30 - 90) * .pi / 180
            let pt = CGPoint(x: cos(t) * R * 0.627, y: sin(t) * R * 0.627)
            var d = abs(Double(i) - head)
            d = min(d, 12 - d)
            let chase = busy * max(0, 1 - d / 2.2)
            let typedLit = lit > i ? (lit > 12 ? 1 : (i == lit - 1 ? 1 : 0.75)) : 0
            let on = min(1, max(typedLit, chase, m.pins))
            // A drilled socket: dark, with a lip of light along its lower edge.
            r.fill(circle(R * 0.02, at: pt), with: .color(p.edge))
            r.stroke(circle(R * 0.02, at: CGPoint(x: pt.x, y: pt.y + 0.6)), with: .color(p.engraveLip.opacity(0.5)), lineWidth: 0.5)
            if on > 0 {
                r.fill(circle(R * 0.05, at: pt), with: .radialGradient(Gradient(colors: [glow(on * 0.55), glow(0)]),
                                                                       center: pt, startRadius: 0, endRadius: R * 0.05))
                r.fill(circle(R * 0.014, at: pt), with: .color(glow(on)))
                r.fill(circle(R * 0.006, at: pt), with: .color(.white.opacity(on * 0.9)))
            }
        }
    }

    private func drawCore(_ l: inout GraphicsContext, p: DoorPalette, glow: RGB) {
        let R = radius
        let rc = DoorGeometry.core * R
        l.fill(circle(rc), with: .linearGradient(Gradient(colors: p.recess), startPoint: CGPoint(x: 0, y: -rc),
                                                 endPoint: CGPoint(x: 0, y: rc)))
        // Recessed: shadowed from the top, a catch of light along the bottom lip.
        l.stroke(circle(rc - 1), with: .linearGradient(Gradient(colors: [p.edge, .clear]), startPoint: CGPoint(x: 0, y: -rc),
                                                       endPoint: CGPoint(x: 0, y: rc * 0.2)), lineWidth: 3)
        l.stroke(circle(rc - 0.5), with: .linearGradient(Gradient(colors: [.clear, p.shine]), startPoint: CGPoint(x: 0, y: 0),
                                                         endPoint: CGPoint(x: 0, y: rc)), lineWidth: 1)
        l.stroke(circle(rc * 0.9), with: .color(glow(dark ? 0.12 : 0.16)), lineWidth: 1)
        // The plates' seams: faint until the hub splits.
        var cross = Path()
        cross.move(to: CGPoint(x: -rc, y: 0)); cross.addLine(to: CGPoint(x: rc, y: 0))
        cross.move(to: CGPoint(x: 0, y: -rc)); cross.addLine(to: CGPoint(x: 0, y: rc))
        l.stroke(cross, with: .color(p.engrave.opacity(0.35)), lineWidth: 0.6)
        // The index the pins turn to.
        var marker = Path()
        marker.move(to: CGPoint(x: 0, y: -rc * 0.955))
        marker.addLine(to: CGPoint(x: -R * 0.016, y: -rc * 0.915))
        marker.addLine(to: CGPoint(x: R * 0.016, y: -rc * 0.915))
        marker.closeSubpath()
        l.fill(marker, with: .color(glow(0.9)))
    }

    // MARK: Motes

    private func drawMotes(_ ctx: inout GraphicsContext, glow: RGB) {
        let R = radius
        func rnd(_ i: Int, _ salt: Double) -> Double {
            let v = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
            return v - floor(v)
        }
        for i in 0..<44 {
            let a = rnd(i, 1) * 2 * .pi + time * (rnd(i, 2) - 0.5) * 0.06
            let dist = R * (1.08 + rnd(i, 3) * 1.25)
            let bob = sin(time * (0.3 + rnd(i, 5) * 0.4) + Double(i)) * R * 0.03
            let pt = CGPoint(x: center.x + cos(a) * dist, y: center.y + sin(a) * dist + bob)
            let twinkle = 0.5 + 0.5 * sin(time * (0.6 + rnd(i, 6)) + Double(i) * 2.1)
            let alpha = (0.12 + 0.4 * twinkle) * (dark ? 1 : 0.8)
            let r = 0.8 + rnd(i, 7) * 1.6
            ctx.fill(circle(r, at: pt), with: .color(glow(alpha)))
        }
    }

    // MARK: Helpers

    private func circle(_ r: CGFloat, at p: CGPoint = .zero) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// A band of turned steel, lit from a fixed light above whatever `turn` the ring is at: a fine concentric
    /// lathe finish, the cross-shaped sheen turned metal throws, a raised outer lip and a chamfered inner edge.
    private func fillBand(_ c: inout GraphicsContext, inner: CGFloat, outer: CGFloat, colors: [Color], turn: Double) {
        let p = DoorPalette(dark: dark)
        var band = circle(outer)
        band.addPath(circle(inner))
        let style = FillStyle(eoFill: true)
        // Light direction in the ring's own (turned) coordinates.
        let back = -turn * .pi / 180
        func lit(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * cos(back) - y * sin(back), y: x * sin(back) + y * cos(back))
        }
        c.fill(band, with: .linearGradient(Gradient(colors: colors), startPoint: lit(-outer * 0.35, -outer),
                                           endPoint: lit(outer * 0.35, outer)), style: style)
        // Anisotropic sheen: bright lobes top-left and bottom-right, darker ones across.
        let hi = Color.white.opacity(dark ? 0.09 : 0.55)
        let lo = Color.black.opacity(dark ? 0.16 : 0.06)
        c.fill(band, with: .conicGradient(Gradient(colors: [hi, .clear, lo, .clear, hi, .clear, lo, .clear, hi]),
                                          center: .zero, angle: .degrees(-135 - turn)), style: style)
        // Lathe rings.
        var r = inner + 1.5
        var i = 0
        while r < outer - 1 {
            c.stroke(circle(r), with: .color(i % 2 == 0 ? Color.white.opacity(dark ? 0.025 : 0.18) : Color.black.opacity(dark ? 0.05 : 0.025)),
                     lineWidth: 0.6)
            r += 1.8
            i += 1
        }
        // Raised outer lip (lit at the top), chamfered inner edge (lit at the bottom).
        c.stroke(circle(outer - 0.75), with: .linearGradient(Gradient(colors: [p.shine, p.edge.opacity(0.6)]),
                                                             startPoint: lit(0, -outer), endPoint: lit(0, outer)), lineWidth: 1.5)
        c.stroke(circle(inner + 0.75), with: .linearGradient(Gradient(colors: [p.edge, p.shine.opacity(0.7)]),
                                                             startPoint: lit(0, -inner), endPoint: lit(0, inner)), lineWidth: 1.5)
    }

    /// An engraved line: the cut, with a lip of light along its lower edge.
    private func engrave(_ c: inout GraphicsContext, _ path: Path, p: DoorPalette, width: CGFloat) {
        c.stroke(path.offsetBy(dx: 0, dy: 0.6), with: .color(p.engraveLip), lineWidth: width)
        c.stroke(path, with: .color(p.engrave), lineWidth: width)
    }
}

// MARK: - Login

/// The login screen's side panel: the same vault door, closed, under the brand and a caption. A successful sign-in
/// opens it like an unlock.
struct LoginDoorStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let ink = dark ? Color.white : Color(red: 0.05, green: 0.16, blue: 0.27)
        GeometryReader { geo in
            let size = geo.size
            let radius = min(size.width * 0.34, size.height * 0.27, 200)
            ZStack {
                VaultDoorStage(radius: radius, center: CGPoint(x: size.width / 2, y: size.height * 0.40), typed: 0, turns: 0,
                               busy: model.isBusy, errorAt: nil, openedAt: model.unlockOpenedAt, closedAt: nil)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "Chiikawarden")
                        .font(.system(size: 20, weight: .semibold)).tracking(-0.3)
                        .foregroundStyle(dark ? Color.brandFill : Color(red: 0.06, green: 0.45, blue: 0.70))
                        .padding(.bottom, 4)
                    Text("Every login,\nbehind one door.")
                        .font(.system(size: 26, weight: .semibold)).tracking(-0.4)
                        .foregroundStyle(ink)
                    Text("Passwords, passkeys, codes and SSH keys — native on your Mac.")
                        .font(.system(size: 13)).foregroundStyle(ink.opacity(0.62))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(36)
                .opacity(model.unlockOpenedAt == nil ? 1 : 0)
                .animation(.easeIn(duration: 0.25), value: model.unlockOpenedAt == nil)
            }
        }
        // Fades out on the right so the stage melts into the form's side (no hard seam).
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.78),
                                     .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }
}
