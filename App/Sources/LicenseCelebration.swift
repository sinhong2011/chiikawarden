import AppKit
import SwiftUI

/// The registered badge: a tail-sky disc with a check. When `celebration` is set (the moment a key registers) it
/// plays once: the disc springs in, the check draws itself, three rings ripple out — the icon's three dials — and
/// confetti bursts and falls (kept low: the Settings card clips what flies above it). About 1.6 s; with Reduce Motion it only fades in. At rest it's just the badge.
struct RegistrationBadge: View {
    /// When the celebration started; nil shows the badge at rest.
    var celebration: Date?
    /// Snapshots: draw this moment of the celebration (seconds in) instead of animating.
    var frozenAt: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing = false

    private static let size: CGFloat = 64
    private static let length: Double = 1.7

    var body: some View {
        TimelineView(.animation(paused: !playing)) { context in
            let t = frozenAt ?? celebration.map { context.date.timeIntervalSince($0) } ?? Self.length
            ZStack {
                if !reduceMotion { rings(t) }
                disc(t)
            }
            .frame(width: Self.size, height: Self.size)
            .overlay {
                if !reduceMotion, t < Self.length {
                    Confetti(t: t).frame(width: 900, height: 220).offset(y: 40).allowsHitTesting(false)
                }
            }
        }
        .onChange(of: celebration) { _, start in play(start) }
        .onAppear { play(celebration) }
    }

    private func play(_ start: Date?) {
        guard let start, frozenAt == nil, Date.now.timeIntervalSince(start) < Self.length else { return }
        playing = true
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        Task {
            try? await Task.sleep(for: .seconds(Self.length))
            playing = false
        }
    }

    private func disc(_ t: Double) -> some View {
        // A damped spring from 0.55: a little overshoot, then still.
        let scale = reduceMotion ? 1 : 1 - 0.45 * exp(-7 * t) * cos(16 * t)
        let draw = reduceMotion ? 1 : easeOut(clamp((t - 0.12) / 0.32))
        return ZStack {
            Circle().fill(Color.brandFill)
            CheckShape()
                .trim(from: 0, to: draw)
                .stroke(Color.onBrandFill, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
        }
        .scaleEffect(max(scale, 0))
        .opacity(reduceMotion ? clamp(t / 0.3) : 1)
    }

    /// Three rings leaving the disc one after another, widening and fading.
    private func rings(_ t: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let u = clamp((t - 0.08 - Double(i) * 0.12) / 0.9)
                Circle()
                    .stroke(Color.brandFill, lineWidth: 2.5 - Double(i) * 0.5)
                    .scaleEffect(1 + easeOut(u) * (0.8 + Double(i) * 0.3))
                    .opacity(u > 0 ? (1 - u) * 0.6 : 0)
            }
        }
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
}

/// The check, drawn as one stroke so it can trace itself.
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.minY + rect.height * 0.52))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.67))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.36))
        return p
    }
}

/// Confetti from the badge's centre: thrown up and out, spinning, pulled down, fading at the end. The same burst
/// every time (fixed seeds), drawn in one Canvas.
private struct Confetti: View {
    var t: Double

    private struct Piece {
        var vx: Double, vy: Double, spin: Double, phase: Double, size: CGSize, round: Bool, color: Color, delay: Double
    }

    private static let colors: [Color] = [
        .brandFill, .brandButton, Color(red: 1, green: 0.80, blue: 0.36), Color(red: 0.98, green: 0.58, blue: 0.64),
        Color(red: 0.55, green: 0.85, blue: 0.66),
    ]

    private static let pieces: [Piece] = {
        var seed: UInt64 = 0x5452_4957
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<48).map { i in
            // Thrown out to both sides and a little up; air drag stops them, then they flutter down.
            let side = next() < 0.5 ? -1.0 : 1.0
            let long = next() < 0.6
            return Piece(vx: side * (120 + next() * 620), vy: -(60 + next() * 170), spin: (next() - 0.5) * 14,
                         phase: next() * .pi * 2,
                         size: long ? CGSize(width: 5, height: 10) : CGSize(width: 6, height: 6), round: !long,
                         color: colors[i % colors.count], delay: next() * 0.1)
        }
    }()

    var body: some View {
        Canvas { context, size in
            let origin = CGPoint(x: size.width / 2, y: size.height / 2 - 40)
            for piece in Self.pieces {
                let s = t - 0.1 - piece.delay
                guard s > 0 else { continue }
                // Drag k = 3/s: reach v/k, then a gentle fall with a little side-to-side flutter.
                let carried = (1 - exp(-3 * s)) / 3
                let x = origin.x + piece.vx * carried + sin(s * 7 + piece.phase) * 5
                let y = origin.y + piece.vy * carried + 95 * s + 40 * s * s
                let fade = min(max((1.55 - s) / 0.45, 0), 1)
                guard fade > 0 else { continue }
                var c = context
                c.opacity = fade
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(piece.spin * s))
                let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                                  width: piece.size.width, height: piece.size.height)
                let shape = piece.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                c.fill(shape, with: .color(piece.color))
            }
        }
    }
}
