import SwiftUI

// Shared controls so every screen speaks the same visual language: soft panel capsules, a tail-sky primary,
// raised white thumbs, no system chrome where it clashes with the window backdrop.

/// Primary (tail-sky gradient, white label) and secondary (soft panel capsule) buttons, regular or small.
struct AppButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .secondary
    var small = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let dark = scheme == .dark
        configuration.label
            .font(.system(size: small ? 12 : 13, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, small ? 12 : 16)
            .frame(height: small ? 28 : 36)
            .foregroundStyle(foreground(dark))
            .background {
                switch kind {
                case .primary:
                    Capsule().fill(Color.brandButton)
                        .shadow(color: Color.brandFill.opacity(configuration.isPressed ? 0.2 : 0.45), radius: configuration.isPressed ? 2 : 6, y: 2)
                case .secondary:
                    Capsule().fill(dark ? Color.white.opacity(configuration.isPressed ? 0.16 : 0.10)
                                        : Color.white.opacity(configuration.isPressed ? 0.6 : 0.9))
                        .overlay(Capsule().strokeBorder(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
                        .shadow(color: .black.opacity(dark ? 0 : 0.05), radius: 3, y: 1)
                case .destructive:
                    Capsule().fill(Color.red.opacity(configuration.isPressed ? 0.18 : 0.10))
                }
            }
            .shadow(color: kind == .primary ? Color.onBrandFill.opacity(0.3) : .clear, radius: 0.8, y: 0.8)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(.capsule)
    }

    private func foreground(_ dark: Bool) -> Color {
        switch kind {
        case .primary: .white
        case .secondary: dark ? .white : Color(red: 0.07, green: 0.09, blue: 0.16)
        case .destructive: .red
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var appPrimary: AppButtonStyle { AppButtonStyle(kind: .primary) }
    static var appSecondary: AppButtonStyle { AppButtonStyle(kind: .secondary) }
    static var appPrimarySmall: AppButtonStyle { AppButtonStyle(kind: .primary, small: true) }
    static var appSecondarySmall: AppButtonStyle { AppButtonStyle(kind: .secondary, small: true) }
    static var appDestructive: AppButtonStyle { AppButtonStyle(kind: .destructive) }
}

/// Capsule tabs with a raised thumb that slides between options.
struct AppSegmented<Value: Hashable>: View {
    let options: [(Value, LocalizedStringKey)]
    @Binding var selection: Value
    @Namespace private var thumb
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.0 == selection
                Button { withAnimation(.spring(duration: 0.3, bounce: 0.15)) { selection = option.0 } } label: {
                    Text(option.1)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(dark ? Color.white.opacity(0.16) : Color.white)
                                    .shadow(color: .black.opacity(dark ? 0.3 : 0.10), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), in: .capsule)
    }
}

/// An on/off chip (e.g. "A-Z"): tail-sky fill when on, outline when off.
struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button { withAnimation(.snappy(duration: 0.15)) { isOn.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark" : "plus").font(.system(size: 10, weight: .bold))
                Text(verbatim: title).font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(isOn ? Color.onBrandFill : .secondary)
            .padding(.horizontal, 12).frame(height: 30)
            .background(isOn ? Color.brandFill : .clear, in: .capsule)
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Color.primary.opacity(scheme == .dark ? 0.18 : 0.14)))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }
}

/// A number in the app's rounded field with − / + on either side, clamped to its range.
struct NumberStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: value > range.lowerBound) { value = max(value - 1, range.lowerBound) }
            TextField("", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }), format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 40)
            stepButton("plus", enabled: value < range.upperBound) { value = min(value + 1, range.upperBound) }
        }
        .frame(height: 32)
        .background(scheme == .dark ? Color.white.opacity(0.07) : Color.white, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .frame(width: 30, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.brand : .secondary.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? Text("Increase") : Text("Decrease"))
    }
}

/// A slim segmented level bar (strength 1–4) or a smooth fraction bar (countdown).
struct LevelBar: View {
    var level: Int? = nil
    var fraction: Double? = nil
    var color: Color = .brand

    var body: some View {
        if let level {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(i < level ? color : Color.primary.opacity(0.10)).frame(height: 4)
                }
            }
        } else {
            GeometryReader { g in
                Capsule().fill(Color.primary.opacity(0.10))
                    .overlay(alignment: .leading) { Capsule().fill(color).frame(width: g.size.width * (fraction ?? 0)) }
            }
            .frame(height: 4)
        }
    }
}
