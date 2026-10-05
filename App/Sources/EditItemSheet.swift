import ChiikawaCrypto
import SwiftUI
import VaultwardenAPI

/// Create or edit a login / secure note. Only changed fields are sent; everything else on the
/// server's copy (passkeys, item key, custom fields, history) is preserved by `CipherEditor`.
struct EditItemSheet: View {
    enum Mode: Equatable {
        case create(AppModel.NewItemKind)
        case edit(VaultItem)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var name = ""
    @State private var username = ""
    @State private var password = ""
    @State private var totp = ""
    @State private var uri = ""
    @State private var notes = ""
    @State private var folderId: String?
    @State private var showPassword = false
    @State private var showGenerator = false
    @State private var saving = false
    @FocusState private var focus: Field?

    enum Field { case name }

    private var isLogin: Bool {
        switch mode {
        case .create(let kind): kind == .login
        case .edit(let item): item.kind == .login
        }
    }

    private var title: LocalizedStringKey {
        switch mode {
        case .create(.login): "New Login"
        case .create(.secureNote): "New Secure Note"
        case .edit: "Edit Item"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: isLogin ? "key.fill" : "note.text")
                    .foregroundStyle(Color.brand)
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 4)
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("e.g. GitHub"))
                        .focused($focus, equals: .name)
                    if !model.folders.isEmpty {
                        Picker("Folder", selection: $folderId) {
                            Text("No Folder").tag(String?.none)
                            ForEach(model.folders) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    }
                }

                if isLogin {
                    Section {
                        TextField("Username", text: $username, prompt: Text(verbatim: "you@example.com"))
                            .textContentType(.username)
                        LabeledContent("Password") {
                            HStack(spacing: 6) {
                                Group {
                                    if showPassword {
                                        TextField("Password", text: $password)
                                    } else {
                                        SecureField("Password", text: $password)
                                    }
                                }
                                .labelsHidden()
                                .font(.system(.body, design: .monospaced))
                                Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }
                                    .buttonStyle(.borderless).help(showPassword ? Text("Hide") : Text("Reveal"))
                                Button { showGenerator = true } label: { Image(systemName: "dice") }
                                    .buttonStyle(.borderless).help(Text("Generate password"))
                                    .popover(isPresented: $showGenerator, arrowEdge: .trailing) {
                                        GeneratorView { generated in
                                            password = generated
                                            showPassword = true
                                            showGenerator = false
                                        }
                                    }
                            }
                        }
                        if !password.isEmpty { StrengthMeter(password: password) }
                        TextField("Website", text: $uri, prompt: Text(verbatim: "https://example.com"))
                            .textContentType(.URL)
                        LabeledContent("One-time code secret") {
                            TextField("One-time code secret", text: $totp, prompt: Text("otpauth://… or base32 key"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .font(.system(.body, design: .monospaced))
                        }
                        if !totp.isEmpty, TOTP(totp) == nil {
                            Label("That doesn't look like a valid one-time code secret.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(minHeight: isLogin ? 70 : 180)
                        .scrollContentBackground(.hidden)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 6) {
                        if saving { ProgressView().controlSize(.small) }
                        Text("Save")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
            .padding(14)
        }
        .frame(width: 520, height: isLogin ? 560 : 420)
        .navigationTitle(title)
        .onAppear(perform: load)
    }

    private func load() {
        focus = .name
        guard case .edit(let item) = mode else { return }
        name = item.name
        username = item.username ?? ""
        password = item.password ?? ""
        totp = item.totpSecret ?? ""
        uri = item.uri ?? ""
        notes = item.notes ?? ""
        folderId = item.folderId
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let ok: Bool
        switch mode {
        case .create(let kind):
            ok = await model.createItem(kind, edit: CipherEdit(
                name: name, notes: notes, username: kind == .login ? username : nil,
                password: kind == .login ? password : nil, totp: kind == .login ? totp : nil,
                uri: kind == .login ? uri : nil, folderId: .some(folderId)))
        case .edit(let item):
            // Send only what changed.
            var edit = CipherEdit()
            if name != item.name { edit.name = name }
            if notes != (item.notes ?? "") { edit.notes = notes }
            if folderId != item.folderId { edit.folderId = .some(folderId) }
            if isLogin {
                if username != (item.username ?? "") { edit.username = username }
                if password != (item.password ?? "") { edit.password = password }
                if totp != (item.totpSecret ?? "") { edit.totp = totp }
                if uri != (item.uri ?? "") { edit.uri = uri }
            }
            ok = edit == CipherEdit() ? true : await model.updateItem(item.id, edit: edit)
        }
        if ok { dismiss() }
    }
}

/// Password generator: length, character classes, look-alike avoidance, entropy meter.
struct GeneratorView: View {
    var onUse: ((String) -> Void)?
    @AppStorage("generator") private var stored = Data()
    @State private var options = PasswordGenerator()
    @State private var value = ""
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: value)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(10)
                .background(.background.secondary, in: .rect(cornerRadius: 8))
                .contentTransition(.opacity)

            StrengthMeter(bits: options.entropyBits)

            HStack {
                Text("Length")
                Slider(value: Binding(get: { Double(options.length) }, set: { options.length = Int($0) }), in: 8...64, step: 1)
                Text(verbatim: "\(options.length)").monospacedDigit().frame(width: 26, alignment: .trailing)
            }
            Toggle("Uppercase (A–Z)", isOn: $options.uppercase)
            Toggle("Lowercase (a–z)", isOn: $options.lowercase)
            Toggle("Digits (0–9)", isOn: $options.digits)
            Toggle("Symbols (!@#…)", isOn: $options.symbols)
            Toggle("Avoid look-alike characters", isOn: $options.avoidAmbiguous)

            HStack {
                Button { regenerate() } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: .command)
                Spacer()
                Button("Copy") { model.copy(value, label: String(localized: "Password")) }
                if let onUse {
                    Button("Use Password") { onUse(value) }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(18)
        .frame(width: 340)
        .onAppear {
            if let saved = try? JSONDecoder().decode(PasswordGenerator.self, from: stored) { options = saved }
            regenerate()
        }
        .onChange(of: options) { _, new in
            stored = (try? JSONEncoder().encode(new)) ?? Data()
            regenerate()
        }
    }

    private func regenerate() { withAnimation(.snappy) { value = options.generate() } }
}

/// Four-segment strength meter.
struct StrengthMeter: View {
    let bits: Double

    init(bits: Double) { self.bits = bits }
    init(password: String) {
        var pool = 0
        if password.contains(where: \.isLowercase) { pool += 26 }
        if password.contains(where: \.isUppercase) { pool += 26 }
        if password.contains(where: \.isNumber) { pool += 10 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { pool += 15 }
        bits = Double(password.count) * log2(Double(max(pool, 2)))
    }

    private var level: (Int, LocalizedStringKey, Color) {
        switch bits {
        case ..<40: (1, "Weak", .red)
        case ..<64: (2, "Fair", .orange)
        case ..<90: (3, "Strong", .green)
        default: (4, "Very strong", .green)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(i < level.0 ? level.2 : Color.secondary.opacity(0.2)).frame(height: 4)
                }
            }
            .frame(width: 120)
            Text(level.1).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .animation(.snappy, value: level.0)
    }
}
