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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0
    @State private var beatScale = 1.0

    var body: some View {
        let urgent = seconds <= 5
        ZStack {
            Circle().stroke(Color.brand.opacity(0.14), lineWidth: size * 0.09)
            Circle()
                .trim(from: 1 - fraction, to: 1)
                .stroke(urgent ? Color.orange : Color.brand, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
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

/// One clock for every one-time code in the app (the codes page, an item's code tile, the menu bar), instead of a
/// timer per view. It ticks four times a second while anything shows a code. Views read only what they need:
/// `second` changes once a second (the code, its seconds), `now` four times (a ring's sweep). A tick so refreshes just
/// those small views — never a list or grid around them — however many codes there are.
@MainActor @Observable
final class OTPClock {
    static let shared = OTPClock()

    private(set) var now = Date.now
    /// Whole seconds since 1970; changes once a second.
    private(set) var second = Int(Date.now.timeIntervalSince1970)

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var users = 0

    /// A view showing a code appeared: the clock runs while there's at least one.
    func retain() {
        users += 1
        guard timer == nil, Motion.plays else { return }
        tick()
        // On the quarter-second, so every ring moves together.
        let next = (Date.now.timeIntervalSince1970 * 4).rounded(.up) / 4
        let timer = Timer(fire: Date(timeIntervalSince1970: next), interval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { OTPClock.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common) // keeps ticking while a menu is open or a scroll is tracking
        self.timer = timer
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 { timer?.invalidate(); timer = nil }
    }

    private func tick() {
        now = .now
        let s = Int(now.timeIntervalSince1970)
        if s != second { second = s } // only on a change, so code views refresh once a second
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

/// A code's countdown ring on the shared clock: its sweep four times a second.
struct LiveCountdownRing: View {
    let totp: TOTP
    var size: CGFloat = 38
    var lively = true
    private let clock = OTPClock.shared

    var body: some View {
        let period = Double(totp.period)
        let fraction = 1 - clock.now.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
        CountdownRing(fraction: fraction, seconds: totp.secondsRemaining(at: clock.now), size: size, lively: lively)
            .frame(width: size, height: size) // a fixed size: a tick never re-lays out anything around it
            .onAppear { clock.retain() }
            .onDisappear { clock.release() }
    }
}
