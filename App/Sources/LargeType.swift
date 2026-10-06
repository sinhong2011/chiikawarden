import AppKit
import SwiftUI

/// A password in big letters over everything, for typing it on a TV, a phone or another computer: each character in
/// its own cell with its position under it; digits and symbols sit on their own kind of tile, and characters that look
/// alike (0 O o, 1 l I |) say what they are. Esc, a click, locking, or two minutes put it away.
@MainActor
enum LargeType {
    private static var panel: NSPanel?
    private static var timeout: Task<Void, Never>?

    static func show(_ text: String) {
        close()
        let hosting = NSHostingView(rootView: LargeTypeView(text: text, dismiss: close))
        hosting.sizingOptions = [.preferredContentSize]
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        CaptureShield.apply(panel)
        panel.onCancel = close
        if let screen = NSScreen.main {
            let size = hosting.fittingSize
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        timeout = Task {
            try? await Task.sleep(for: .seconds(120))
            if !Task.isCancelled { close() }
        }
    }

    static func close() {
        timeout?.cancel()
        timeout = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Borderless panels don't take keys unless asked; this one needs Esc.
    private final class KeyPanel: NSPanel {
        var onCancel: () -> Void = {}
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { onCancel() }
    }
}

struct LargeTypeView: View {
    let text: String
    var dismiss: () -> Void = {}

    /// Rows short enough to read across without losing your place.
    private var rows: [[(Int, Character)]] {
        let chars = Array(text.enumerated())
        let width = chars.count <= 20 ? max(chars.count, 1) : 16
        return stride(from: 0, to: chars.count, by: width).map { Array(chars[$0..<min($0 + width, chars.count)]) }
    }

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.0) { index, char in
                        LargeTypeCell(char: char, position: index + 1)
                    }
                }
            }
            Text("\(text.count) characters · Esc or click to close")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(28)
        .background(.regularMaterial, in: .rect(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.panelEdge))
        .contentShape(.rect)
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text.map(String.init).joined(separator: " ")))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { dismiss() }
    }
}

private struct LargeTypeCell: View {
    let char: Character
    let position: Int

    enum Kind { case letter, digit, symbol, space }
    private var kind: Kind {
        if char == " " { return .space }
        if char.isNumber { return .digit }
        if char.isLetter { return .letter }
        return .symbol
    }

    /// What a look-alike character is, so 0 and O (or l, 1, I and |) can't be mixed up.
    private var hint: LocalizedStringKey? {
        switch char {
        case "0", "1": "digit"
        case "O", "I": "capital"
        case "o", "l": "small"
        case "|": "bar"
        case " ": "space"
        default: nil
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: char == " " ? "␣" : String(char))
                .font(.system(size: 46, weight: .medium, design: .monospaced))
                .foregroundStyle(kind == .space ? .secondary : .primary)
                .frame(minWidth: 44, minHeight: 60)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                    switch kind {
                    case .digit: shape.fill(Color.primary.opacity(0.09))
                    case .symbol: shape.strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    case .letter, .space: Color.clear
                    }
                }
            Text(verbatim: "\(position)")
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(.secondary)
            Text(hint ?? " ")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: 10)
        }
    }
}
