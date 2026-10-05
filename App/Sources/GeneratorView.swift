import ChiikawaCrypto
import SwiftUI

/// Passwords, passphrases and usernames. The full page (Sidebar › Generator) shows every option in cards;
/// the compact form is the popover next to a password field.
struct GeneratorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case password, passphrase, username
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self { case .password: "Password"; case .passphrase: "Passphrase"; case .username: "Username" }
        }
    }

    var modes: [Mode] = Mode.allCases
    var compact = false
    /// Shown as a “Use” button (e.g. from the edit sheet).
    var onUse: ((String) -> Void)?

    @Environment(AppModel.self) private var model
    @AppStorage("generatorMode") private var storedMode = Mode.password.rawValue
    @AppStorage("generator") private var storedPassword = Data()
    @AppStorage("passphraseGenerator") private var storedPassphrase = Data()
    @AppStorage("usernameGenerator") private var storedUsername = Data()
    @State private var password = PasswordGenerator()
    @State private var passphrase = PassphraseGenerator()
    @State private var username = UsernameGenerator()
    @State private var value = ""
    @State private var loaded = false
    @State private var copied = false

    private var mode: Mode {
        let m = Mode(rawValue: storedMode) ?? .password
        return modes.contains(m) ? m : modes[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            if modes.count > 1 {
                AppSegmented(options: modes.map { ($0, $0.title) },
                             selection: Binding(get: { mode }, set: { storedMode = $0.rawValue }))
            }

            output

            if !compact { Text("Options").font(.system(size: 13, weight: .semibold)).padding(.top, 2) }
            Group {
                switch mode {
                case .password: passwordOptions
                case .passphrase: passphraseOptions
                case .username: usernameOptions
                }
            }
            .modifier(OptionsCard(enabled: !compact))

            if let onUse {
                HStack {
                    Spacer()
                    Button(mode == .username ? "Use Username" : "Use Password") { remember(); onUse(value) }
                        .buttonStyle(.appPrimary)
                        .disabled(value.isEmpty)
                }
            }
            if !compact { HistorySection() }
        }
        .padding(compact ? 16 : 0)
        .frame(width: compact ? 360 : nil)
        .onAppear(perform: load)
        .onChange(of: password) { save(); regenerate() }
        .onChange(of: passphrase) { save(); regenerate() }
        .onChange(of: username) { save(); regenerate() }
        .onChange(of: storedMode) { regenerate() }
    }

    // MARK: Output

    private var output: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                ColoredSecret(value: value, separator: mode == .passphrase ? passphrase.separator : nil)
                    .font(.system(size: compact ? 15 : 17, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                    .accessibilityLabel(Text(verbatim: value))
                iconButton("arrow.clockwise", help: "Regenerate") { regenerate() }
                    .keyboardShortcut("r", modifiers: .command)
                iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copy") { copy() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            if mode != .username {
                StrengthMeter(bits: mode == .password ? password.entropyBits : passphrase.entropyBits)
            } else if value.isEmpty {
                Text(username.kind == .plusAddressed ? "Enter your email address below." : "Enter your catch-all domain below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(compact ? 12 : 18)
        .background(Color.panelStrong, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.panelEdge))
    }

    private func iconButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06), in: .circle)
                .contentShape(.circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }

    // MARK: Options

    @ViewBuilder private var passwordOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            NumberRow(label: "Length", value: $password.length, range: PasswordGenerator.lengthRange,
                      hint: "Value must be between 5 and 128.", slider: true)
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 8) {
                OptionLabel("Include")
                HStack(spacing: 8) {
                    ToggleChip(title: "A-Z", isOn: $password.uppercase)
                    ToggleChip(title: "a-z", isOn: $password.lowercase)
                    ToggleChip(title: "0-9", isOn: $password.digits)
                    ToggleChip(title: "!@#$%^&*", isOn: $password.symbols)
                }
            }
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    OptionLabel("Minimum numbers")
                    NumberStepper(value: $password.minNumbers, range: 0...9)
                }
                .disabled(!password.digits).opacity(password.digits ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 8) {
                    OptionLabel("Minimum special")
                    NumberStepper(value: $password.minSpecial, range: 0...9)
                }
                .disabled(!password.symbols).opacity(password.symbols ? 1 : 0.5)
                Spacer()
            }
            Divider().opacity(0.4)
            SwitchRow("Avoid ambiguous characters", isOn: $password.avoidAmbiguous)
        }
    }

    @ViewBuilder private var passphraseOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            NumberRow(label: "Number of words", value: $passphrase.words, range: PassphraseGenerator.wordRange,
                      hint: "Value must be between 3 and 20. Use 6 words or more to generate a strong passphrase.", slider: true)
            Divider().opacity(0.4)
            HStack {
                OptionLabel("Word separator")
                Spacer()
                TextField("", text: $passphrase.separator)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 56, height: 32)
                    .background(Color.primary.opacity(0.05), in: .capsule)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
                    .onChange(of: passphrase.separator) { _, new in if new.count > 3 { passphrase.separator = String(new.prefix(3)) } }
                    .accessibilityLabel(Text("Word separator"))
            }
            SwitchRow("Capitalize", isOn: $passphrase.capitalize)
            SwitchRow("Include number", isOn: $passphrase.includeNumber)
        }
    }

    @ViewBuilder private var usernameOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppSegmented(options: [(UsernameGenerator.Kind.randomWord, "Random word"),
                                   (.plusAddressed, "Plus-addressed email"), (.catchAll, "Catch-all email")],
                         selection: $username.kind)
            switch username.kind {
            case .randomWord:
                SwitchRow("Capitalize", isOn: $username.capitalize)
                SwitchRow("Include number", isOn: $username.includeNumber)
            case .plusAddressed:
                TextField("Email", text: $username.email, prompt: Text(verbatim: "you@example.com")).textFieldStyle(SoftFieldStyle())
                Text("Adds a random tag, e.g. you+k3x9q2ma@example.com, so you can tell who shared your address.")
                    .font(.caption).foregroundStyle(.secondary)
            case .catchAll:
                TextField("Domain", text: $username.domain, prompt: Text(verbatim: "example.com")).textFieldStyle(SoftFieldStyle())
                Text("A random address at a domain that accepts any mailbox.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: State

    private func load() {
        guard !loaded else { return }
        if let p = try? JSONDecoder().decode(PasswordGenerator.self, from: storedPassword) { password = p }
        if let p = try? JSONDecoder().decode(PassphraseGenerator.self, from: storedPassphrase) { passphrase = p }
        if let u = try? JSONDecoder().decode(UsernameGenerator.self, from: storedUsername) { username = u }
        if username.email.isEmpty { username.email = model.sessions.first?.account.email ?? "" }
        loaded = true
        regenerate()
    }

    private func save() {
        storedPassword = (try? JSONEncoder().encode(password)) ?? storedPassword
        storedPassphrase = (try? JSONEncoder().encode(passphrase)) ?? storedPassphrase
        storedUsername = (try? JSONEncoder().encode(username)) ?? storedUsername
    }

    private func regenerate() {
        withAnimation(.snappy(duration: 0.2)) {
            switch mode {
            case .password: value = password.generate()
            case .passphrase: value = passphrase.generate()
            case .username: value = username.generate() ?? ""
            }
        }
    }

    private func copy() {
        guard !value.isEmpty else { return }
        model.copy(value, label: mode == .username ? String(localized: "Username") : String(localized: "Password"))
        remember()
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.snappy) { copied = false }
        }
    }

    private func remember() { model.rememberGenerated(value, kind: mode.rawValue) }
}

/// Digits in brand blue, symbols (and passphrase separators) in coral, letters in the text colour.
struct ColoredSecret: View {
    let value: String
    var separator: String?

    var body: some View {
        var text = AttributedString()
        for ch in value {
            var piece = AttributedString(String(ch))
            if ch.isNumber {
                piece.foregroundColor = .brand
            } else if let separator, separator.contains(ch) {
                piece.foregroundColor = Color(red: 0.90, green: 0.32, blue: 0.36)
            } else if !ch.isLetter {
                piece.foregroundColor = Color(red: 0.90, green: 0.32, blue: 0.36)
            }
            text += piece
        }
        return Text(text)
    }
}

/// A labelled number: brand slider plus the shared − / + stepper, clamped to its range.
private struct NumberRow: View {
    let label: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var hint: LocalizedStringKey?
    var slider = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OptionLabel(label)
            HStack(spacing: 14) {
                if slider {
                    Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                           in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                        .labelsHidden()
                        .tint(.brand)
                }
                NumberStepper(value: $value, range: range)
            }
            if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct OptionLabel: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View { Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
}

/// A label with a small switch on the right.
private struct SwitchRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) { self.title = title; _isOn = isOn }
    var body: some View {
        Toggle(isOn: $isOn) { Text(title).font(.system(size: 13)) }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(.brand)
    }
}

private struct OptionsCard: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.panelStrong, in: .rect(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.panelEdge))
        } else {
            content
        }
    }
}

/// Recently copied or used values. In memory only; cleared when the vault locks.
private struct HistorySection: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack {
                    Text("Generator history").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.brand)
                    Text(verbatim: "\(model.generatorHistory.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.brand)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 18).frame(height: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if expanded {
                if model.generatorHistory.isEmpty {
                    Text("Values you copy or use appear here until the vault locks.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.bottom, 14)
                } else {
                    ForEach(model.generatorHistory) { entry in
                        HStack(spacing: 10) {
                            ColoredSecret(value: entry.value).font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(entry.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                            Button { model.copy(entry.value, label: String(localized: "Password")) } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 12))
                            }
                            .buttonStyle(.borderless)
                            .help(Text("Copy"))
                            .accessibilityLabel(Text("Copy"))
                        }
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .overlay(alignment: .top) { Divider().opacity(0.5) }
                    }
                    HStack {
                        Spacer()
                        Button("Clear History", role: .destructive) {
                            model.confirm(String(localized: "Clear generator history?"),
                                          message: String(localized: "The values listed here are forgotten. Items you saved are not affected."),
                                          action: String(localized: "Clear History")) { model.generatorHistory.removeAll() }
                        }
                            .buttonStyle(.borderless).font(.caption)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                }
            }
        }
        .background(Color.panelStrong, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.panelEdge))
    }
}
