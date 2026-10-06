import AppKit
import SwiftUI

/// A one-time code typed into six cells (in two groups of three). One hidden field takes the input, so typing,
/// deleting, pasting a whole code and macOS's "From Mail" suggestion all work; spaces and dashes are dropped.
/// It calls `onComplete` as soon as every cell is filled.
struct CodeEntry: View {
    @Binding var code: String
    var length = 6
    /// Shows the cells in red (a code the server refused), until the next keystroke.
    var rejected = false
    var onComplete: () -> Void = {}

    @FocusState private var focused: Bool
    @State private var clipboardCode: String?
    @State private var refusals = 0
    @Environment(\.colorScheme) private var scheme

    private var digits: [Character] { Array(code) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                // The field that really takes the keys; the cells below draw what it holds.
                TextField("", text: Binding(get: { code }, set: { accept($0) }))
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .opacity(0.02)
                    .accessibilityLabel(Text("Verification code"))
                HStack(spacing: 8) {
                    ForEach(0..<length, id: \.self) { index in
                        if index == length / 2 {
                            Capsule().fill(Color.primary.opacity(0.18)).frame(width: 10, height: 2).padding(.horizontal, 2)
                        }
                        cell(index)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture { focused = true }
                .accessibilityHidden(true)
            }
            .frame(height: 58)
            .shake(on: refusals)
            .onChange(of: rejected) { _, now in if now { refusals += 1 } }

            if let clipboardCode, clipboardCode != code {
                Button { accept(clipboardCode) } label: {
                    Label {
                        Text("Paste \(grouped(clipboardCode))").monospacedDigit()
                    } icon: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.appSecondarySmall)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.2), value: clipboardCode)
        .onAppear {
            focused = true
            readClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in readClipboard() }
    }

    private func cell(_ index: Int) -> some View {
        let filled = index < digits.count
        let active = focused && (index == digits.count || (index == length - 1 && digits.count == length))
        let border: Color = rejected ? .red.opacity(0.75) : active ? Color.primary.opacity(0.4) : Color(nsColor: .separatorColor)
        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                // Filled cells sit up a little: white in light mode, a lighter step in dark mode.
                .fill(filled ? (scheme == .dark ? Color.white.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                             : Color.primary.opacity(scheme == .dark ? 0.04 : 0.035))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(border, lineWidth: active || rejected ? 1.5 : 1)
            if filled {
                Text(String(digits[index]))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(rejected ? Color.red : .primary)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .id(digits[index])
            } else if active {
                Caret()
            }
        }
        .frame(minWidth: 40, maxWidth: 56, minHeight: 58, maxHeight: 58) // fills the form's width, edge to edge
        .shadow(color: .black.opacity(filled && scheme == .light ? 0.06 : 0), radius: 3, y: 1)
        .animation(.spring(duration: 0.28, bounce: 0.35), value: filled)
        .animation(.easeOut(duration: 0.15), value: active)
    }

    /// Keeps digits only, up to `length`; a full code submits.
    private func accept(_ text: String) {
        let clean = String(text.filter(\.isNumber).prefix(length))
        guard clean != code else { return }
        withAnimation(.spring(duration: 0.28, bounce: 0.35)) { code = clean }
        if clean.count == length { onComplete() }
    }

    /// A code on the clipboard (6 digits, maybe spaced or dashed), offered as one click.
    private func readClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let digits = text.filter(\.isNumber)
        let onlyCode = text.allSatisfy { $0.isNumber || $0 == " " || $0 == "-" }
        clipboardCode = onlyCode && digits.count == length ? digits : nil
    }

    private func grouped(_ code: String) -> String {
        code.count == 6 ? code.prefix(3) + " " + code.suffix(3) : code
    }
}

/// The blinking insertion point in the cell that takes the next digit.
private struct Caret: View {
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.primary)
            .frame(width: 2, height: 24)
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = false }
            }
    }
}

/// "Send a new code", then a short wait before it can be asked again.
struct ResendCodeButton: View {
    let action: () async -> Void
    var cooldown = 30
    @State private var sentAt: Date?
    @State private var sending = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = sentAt.map { max(0, cooldown - Int(context.date.timeIntervalSince($0))) } ?? 0
            Button {
                Task {
                    sending = true
                    await action()
                    sending = false
                    sentAt = .now
                }
            } label: {
                if left > 0 {
                    Text("Send again in \(left) s").monospacedDigit().contentTransition(.numericText(countsDown: true))
                } else {
                    Text("Send a new code")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(left > 0 || sending ? Color.secondary.opacity(0.7) : .secondary)
            .underline(left == 0 && !sending, color: .secondary.opacity(0.5))
            .disabled(left > 0 || sending)
            .animation(.snappy, value: left)
        }
    }
}
