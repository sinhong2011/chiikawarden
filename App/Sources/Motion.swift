import SwiftUI

/// A secret that decodes as it's shown: every character flickers through random glyphs and settles, left to right
/// (~0.4 s). With Reduce Motion it just appears. The glyphs are random, so the flicker gives nothing away.
struct DecodingText: View {
    let text: String
    @State private var shown: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let glyphs = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789#$%&*+=?")

    init(_ text: String) {
        self.text = text
        _shown = State(initialValue: Self.scramble(text, keeping: 0))
    }

    var body: some View {
        Text(verbatim: shown)
            .task(id: text) {
                guard !reduceMotion, !text.isEmpty else { shown = text; return }
                let steps = 14
                for step in 0...steps {
                    // Settled characters lead; the rest keep flickering.
                    shown = Self.scramble(text, keeping: text.count * step / steps)
                    try? await Task.sleep(for: .milliseconds(28))
                    if Task.isCancelled { break }
                }
                shown = text
            }
    }

    private static func scramble(_ text: String, keeping settled: Int) -> String {
        String(text.enumerated().map { index, char in
            index < settled || char == " " ? char : glyphs.randomElement()!
        })
    }
}

/// Ticks once *this* control's copy has landed (after any master-password prompt): `copied` turns on for a moment,
/// with a light tap on the trackpad. Call `arm()` just before copying.
struct CopyTick: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var armed: Int?
    @Binding var copied: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: model.copyCount) { _, now in
                guard let armed, now > armed else { return }
                self.armed = nil
                withAnimation(.snappy(duration: 0.25)) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    if model.copyCount == now { withAnimation(.snappy(duration: 0.3)) { copied = false } }
                }
            }
            .sensoryFeedback(.alignment, trigger: copied) { _, new in new }
    }
}

extension View {
    func copyTick(armed: Binding<Int?>, copied: Binding<Bool>) -> some View {
        modifier(CopyTick(armed: armed, copied: copied))
    }
}

/// A row that has just been created pops once as it lands in the list.
struct ArrivalPop: ViewModifier {
    let arrived: Bool
    @State private var beat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: beat) { row, scale in
                row.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0.94, duration: 0.08)
                    SpringKeyframe(1.03, duration: 0.18, spring: .snappy)
                    SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                }
            }
            .onAppear { if arrived, !reduceMotion { beat += 1 } }
            .onChange(of: arrived) { _, now in if now, !reduceMotion { beat += 1 } }
    }
}
