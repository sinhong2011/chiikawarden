import SwiftUI

/// A one-time code as two halves with a softly breathing dot between them: "485 • 657".
struct OTPCode: View {
    let code: String
    var size: CGFloat = 26
    /// Last seconds of the period: the dot turns orange.
    var urgent = false

    var body: some View {
        let split = code.count / 2
        HStack(spacing: size * 0.3) {
            half(String(code.prefix(split)), from: 0)
            BreathingDot(diameter: size * 0.24, color: urgent ? .orange : .brand)
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
                .contentTransition(Motion.plays ? .numericText(countsDown: true) : .identity)
        }
        .frame(width: size, height: size)
        .animation(Motion.plays ? .snappy : nil, value: seconds)
        .keyframeAnimator(initialValue: 1.0, trigger: beat) { ring, scale in
            ring.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(beatScale, duration: 0.1)
                SpringKeyframe(1, duration: 0.45, spring: .bouncy)
            }
        }
        .onChange(of: seconds) { old, new in
            guard !reduceMotion else { return }
            if new > old { beatScale = 1.16; beat += 1 }           // a new code
            else if new <= 5 { beatScale = 1.07; beat += 1 }       // the last seconds
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(seconds) seconds left"))
    }
}
