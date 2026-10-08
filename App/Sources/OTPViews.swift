import SwiftUI
import TriCrypto

/// A one-time code as two halves with a softly breathing dot between them: "485 • 657".
struct OTPCode: View {
    let code: String
    var size: CGFloat = 26
    /// Last seconds of the period: the dot turns orange.
    var urgent = false
    /// The dot breathes (one code on its own); a grid of codes keeps it still, which is far lighter.
    var breathing = true

    var body: some View {
        let split = code.count / 2
        HStack(spacing: size * 0.3) {
            half(String(code.prefix(split)), from: 0)
            Group {
                if breathing {
                    BreathingDot(diameter: size * 0.24, color: urgent ? .orange : .brand)
                } else {
                    Circle().fill(urgent ? Color.orange : Color.brand)
                }
            }
            .frame(width: size * 0.24, height: size * 0.24) // the halo grows without moving anything
            half(String(code.suffix(code.count - split)), from: split)
        }
        .font(.system(size: size, weight: .semibold, design: .monospaced))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: code))
    }
}

extension OTPCode {
    /// Each half keeps the width of its digit count, so the dot never shifts while digits roll over (each digit rolls
    /// on its own, like a flip clock).
    fileprivate func half(_ digits: String, from start: Int) -> some View {
        Text(verbatim: String(repeating: "0", count: digits.count))
            .fixedSize() // never squeezed narrower than the digits drawn over it
            .hidden()
            .overlay(alignment: .leading) {
                Text(verbatim: digits)
                    .contentTransition(.numericText())
                    .fixedSize()
                    .animation(Motion.plays ? .spring(duration: 0.45, bounce: 0.2).delay(Double(start) * 0.06) : nil, value: digits)
            }
    }
}

/// A small dot that breathes: it swells gently while a soft halo blooms out from it and fades.
struct BreathingDot: View {
    let diameter: CGFloat
    var color: Color = .brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion || !Motion.plays {
            Circle().fill(color).frame(width: diameter, height: diameter)
        } else {
            PhaseAnimator([false, true]) { inhale in
                ZStack {
                    Circle()
                        .fill(color.opacity(0.35))
                        .scaleEffect(inhale ? 2.6 : 1)
                        .opacity(inhale ? 0 : 0.7)
                    Circle()
                        .fill(color)
                        .scaleEffect(inhale ? 1 : 0.72)
                        .opacity(inhale ? 1 : 0.6)
                }
                .frame(width: diameter, height: diameter)
            } animation: { inhale in
                inhale ? .easeOut(duration: 1.4) : .easeInOut(duration: 1.0)
            }
            .accessibilityHidden(true)
        }
    }
}

/// Seconds left in the code's period, as a ring that drains clockwise with the number inside.
/// It pops when a new code starts the ring again, and ticks with a smaller pop through the last five seconds.
struct CountdownRing: View {
    let fraction: Double
    let seconds: Int
    var size: CGFloat = 38
    /// The seconds' size against the ring's: larger for a small ring that stands on its own.
    var digits: CGFloat = 0.32
    /// The number rolls and the ring pops each second. Off in a grid of codes: dozens of rings animating every second
    /// keep the whole window redrawing.
    var lively = true
    /// Seconds until the ring is empty: given, the arc drains on its own (Core Animation, smooth, no per-frame work);
    /// otherwise it's drawn at `fraction` and moves only when redrawn.
    var drainsIn: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0
    @State private var beatScale = 1.0

    var body: some View {
        let urgent = seconds <= 5
        ZStack {
            Circle().stroke(Color.brand.opacity(0.14), lineWidth: size * 0.09)
            if let drainsIn, Motion.plays {
                SweepArc(fraction: fraction, drainsIn: drainsIn, color: urgent ? .orange : .brand, lineWidth: size * 0.09)
            } else {
                Circle()
                    .trim(from: 1 - fraction, to: 1)
                    .stroke(urgent ? Color.orange : Color.brand, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(verbatim: "\(seconds)")
                .font(.system(size: size * digits, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(urgent ? Color.orange : .secondary)
                .contentTransition(Motion.plays && lively ? .numericText(countsDown: true) : .identity)
        }
        .frame(width: size, height: size)
        .animation(Motion.plays && lively ? .snappy : nil, value: seconds)
        .keyframeAnimator(initialValue: 1.0, trigger: beat) { ring, scale in
            ring.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(beatScale, duration: 0.1)
                SpringKeyframe(1, duration: 0.45, spring: .bouncy)
            }
        }
        .onChange(of: seconds) { old, new in
            guard !reduceMotion, lively else { return }
            if new > old { beatScale = 1.16; beat += 1 }           // a new code
            else if new <= 5 { beatScale = 1.07; beat += 1 }       // the last seconds
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(seconds) seconds left"))
    }
}

/// One clock for every one-time code in the app (the codes page, an item's code tile, the menu bar, the palette),
/// instead of a timer per view. It ticks once a second, on the second, while anything shows a code; codes and their
/// seconds read it, and rings use it to restart a smooth Core Animation sweep (`SweepArc`). A tick so refreshes just
/// those small views — never a list or grid around them — however many codes there are.
@MainActor @Observable
final class OTPClock {
    static let shared = OTPClock()

    /// Whole seconds since 1970; changes once a second.
    private(set) var second = Int(Date.now.timeIntervalSince1970)

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var users = 0

    /// A view showing a code appeared: the clock runs while there's at least one.
    func retain() {
        users += 1
        guard timer == nil, Motion.plays else { return }
        tick()
        let next = Date.now.timeIntervalSince1970.rounded(.up)
        let timer = Timer(fire: Date(timeIntervalSince1970: next), interval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { OTPClock.shared.tick() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common) // keeps ticking while a menu is open or a scroll is tracking
        self.timer = timer
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 { timer?.invalidate(); timer = nil }
    }

    private func tick() {
        let s = Int(Date.now.timeIntervalSince1970.rounded())
        if s != second { second = s }
    }
}

/// A one-time code on the shared clock: refreshed once a second.
struct LiveOTPCode: View {
    let totp: TOTP
    var size: CGFloat = 26
    var breathing = true
    private let clock = OTPClock.shared

    var body: some View {
        let date = Date(timeIntervalSince1970: TimeInterval(clock.second))
        OTPCode(code: totp.code(at: date), size: size, urgent: totp.secondsRemaining(at: date) <= 5, breathing: breathing)
            .onAppear { clock.retain() }
            .onDisappear { clock.release() }
    }
}

/// A code's countdown ring on the shared clock: once a second it sets the seconds and restarts the arc's sweep,
/// which then drains smoothly by itself until the next tick.
struct LiveCountdownRing: View {
    let totp: TOTP
    var size: CGFloat = 38
    var lively = true
    private let clock = OTPClock.shared

    var body: some View {
        _ = clock.second // refresh on each tick
        let now = Date.now
        let period = Double(totp.period)
        let into = now.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
        return CountdownRing(fraction: 1 - into / period, seconds: totp.secondsRemaining(at: now), size: size, lively: lively,
                             drainsIn: period - into)
            .frame(width: size, height: size) // a fixed size: a tick never re-lays out anything around it
            .onAppear { clock.retain() }
            .onDisappear { clock.release() }
    }
}

/// A ring's arc that drains clockwise to empty over `drainsIn` seconds, animated by Core Animation (the render server
/// draws every frame; the app does nothing between updates). Starts at 12 o'clock, like the drawn ring.
struct SweepArc: NSViewRepresentable {
    let fraction: Double
    let drainsIn: TimeInterval
    let color: Color
    let lineWidth: CGFloat

    func makeNSView(context: Context) -> ArcView { ArcView() }

    func updateNSView(_ view: ArcView, context: Context) {
        view.update(fraction: fraction, drainsIn: drainsIn, color: NSColor(color), lineWidth: lineWidth)
    }

    final class ArcView: NSView {
        private let arc = CAShapeLayer()
        private var color = NSColor.controlAccentColor

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            arc.fillColor = nil
            arc.lineCap = .round
            arc.strokeEnd = 1
            layer?.addSublayer(arc)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil } // clicks go to the card or tile underneath

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.frame = bounds
            let inset = arc.lineWidth / 2
            let rect = bounds.insetBy(dx: inset, dy: inset)
            let path = CGMutablePath()
            // From 12 o'clock all the way round, travelling clockwise on screen (the arc left showing ends at 12, like
            // the drawn ring). Checked against a capture: this layer's arcs run opposite to the flag's name.
            path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                        startAngle: .pi / 2, endAngle: .pi / 2 + 2 * .pi, clockwise: false)
            arc.path = path
            CATransaction.commit()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            recolor()
        }

        private func recolor() {
            effectiveAppearance.performAsCurrentDrawingAppearance { arc.strokeColor = color.cgColor }
        }

        func update(fraction: Double, drainsIn: TimeInterval, color: NSColor, lineWidth: CGFloat) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.color = color
            recolor()
            if arc.lineWidth != lineWidth { arc.lineWidth = lineWidth; needsLayout = true }
            // The visible arc is the part after strokeStart: from where it is now, sweep to empty.
            arc.strokeStart = 1
            let sweep = CABasicAnimation(keyPath: "strokeStart")
            sweep.fromValue = 1 - fraction
            sweep.toValue = 1
            sweep.duration = max(drainsIn, 0.01)
            sweep.timingFunction = CAMediaTimingFunction(name: .linear)
            arc.add(sweep, forKey: "sweep") // replaces last second's, from the same point: no jump
            CATransaction.commit()
        }
    }
}
