import AppKit
import SwiftUI

/// Rounded field used on the login, unlock and AutoFill screens.
struct SoftFieldStyle: TextFieldStyle {
    var height: CGFloat = 38
    /// Room on the right for an accessory inside the field (the reveal button).
    var trailingInset: CGFloat = 0
    @FocusState private var focused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.leading, 12)
            .padding(.trailing, 12 + trailingInset)
            .frame(height: height)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    // Focus: a firmer neutral outline — no colour, no glow.
                    .strokeBorder(focused ? Color.primary.opacity(0.35) : Color(nsColor: .separatorColor), lineWidth: focused ? 1.5 : 1)
            )
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// A password field with a show/hide button. Toggling keeps the cursor in the field.
struct PasswordField: View {
    enum Look { case soft, rounded, plain }

    let title: LocalizedStringKey
    @Binding var text: String
    var look: Look = .soft
    var prompt: Text? = Text(verbatim: "")
    /// Optional link to the caller's focus state.
    var isFocused: Binding<Bool>?
    var onSubmit: () -> Void = {}

    @State private var visible = false
    @FocusState private var focused: Bool
    /// Caps Lock is on: worth a word while typing a password you can't see.
    @State private var capsLock = NSEvent.modifierFlags.contains(.capsLock)
    @State private var capsMonitor: Any?

    private var showsCapsLock: Bool { capsLock && focused && !visible }

    var body: some View {
        ZStack(alignment: .trailing) {
            styled(Group {
                if visible {
                    TextField(title, text: $text, prompt: prompt)
                } else {
                    SecureField(title, text: $text, prompt: prompt)
                }
            })
            .textContentType(.password)
            .labelsHidden()
            .focused($focused)
            .onSubmit(onSubmit)

            HStack(spacing: 0) {
                if showsCapsLock {
                    Image(systemName: "capslock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 26)
                        .help(Text("Caps Lock is on"))
                        .accessibilityLabel(Text("Caps Lock is on"))
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
                Button {
                    visible.toggle()
                    focused = true
                } label: {
                    Image(systemName: visible ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(visible ? Text("Hide password") : Text("Show password"))
                .accessibilityLabel(visible ? Text("Hide password") : Text("Show password"))
            }
            .padding(.trailing, look == .plain ? 0 : 6)
            .animation(.snappy(duration: 0.2), value: showsCapsLock)
        }
        .onAppear {
            capsLock = NSEvent.modifierFlags.contains(.capsLock)
            capsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                capsLock = event.modifierFlags.contains(.capsLock)
                return event
            }
        }
        .onDisappear { capsMonitor.map(NSEvent.removeMonitor); capsMonitor = nil }
        .onChange(of: focused) { _, now in if isFocused?.wrappedValue != now { isFocused?.wrappedValue = now } }
        .onChange(of: isFocused?.wrappedValue) { _, wanted in if let wanted, wanted != focused { focused = wanted } }
        .onAppear { if isFocused?.wrappedValue == true { focused = true } }
        .onDisappear { visible = false }
    }

    @ViewBuilder
    private func styled(_ field: some View) -> some View {
        switch look {
        case .soft: field.textFieldStyle(SoftFieldStyle(trailingInset: showsCapsLock ? 44 : 22))
        case .rounded: field.textFieldStyle(.roundedBorder).padding(.trailing, 0)
        case .plain: field.textFieldStyle(.plain).padding(.trailing, showsCapsLock ? 50 : 28) // room for the reveal button
        }
    }
}

extension FocusState<Bool>.Binding {
    /// A plain Bool binding over a FocusState, for `PasswordField(isFocused:)`.
    var wrappedBinding: Binding<Bool> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
