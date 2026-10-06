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
            half(String(code.prefix(split)))
            BreathingDot(diameter: size * 0.24, color: urgent ? .orange : .brand)
                .frame(width: size * 0.24, height: size * 0.24) // the halo grows without moving anything
            half(String(code.suffix(code.count - split)))
        }
        .font(.system(size: size, weight: .semibold, design: .monospaced))
        .animation(.snappy, value: code)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: code))
    }
}

extension OTPCode {
    /// Each half keeps the width of its digit count, so the dot never shifts while digits roll over.
    fileprivate func half(_ digits: String) -> some View {
        Text(verbatim: String(repeating: "0", count: digits.count))
            .fixedSize() // never squeezed narrower than the digits drawn over it
            .hidden()
            .overlay(alignment: .leading) {
                Text(verbatim: digits).contentTransition(.numericText()).fixedSize()
            }
    }
}

/// A small dot that breathes: it swells gently while a soft halo blooms out from it and fades.
struct BreathingDot: View {
    let diameter: CGFloat
    var color: Color = .brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
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
struct CountdownRing: View {
    let fraction: Double
    let seconds: Int
    var size: CGFloat = 38

    var body: some View {
        let urgent = seconds <= 5
        ZStack {
            Circle().stroke(Color.brand.opacity(0.14), lineWidth: size * 0.09)
            Circle()
                .trim(from: 1 - fraction, to: 1)
                .stroke(urgent ? Color.orange : Color.brand, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(seconds)")
                .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(urgent ? Color.orange : .secondary)
                .contentTransition(.numericText(countsDown: true))
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: seconds)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(seconds) seconds left"))
    }
}
