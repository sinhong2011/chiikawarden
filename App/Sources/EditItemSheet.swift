import ChiikawaCrypto
import SwiftUI
import VaultwardenAPI

/// Create or edit any item type. Only changed fields are sent; everything else on the server's copy
/// (passkeys, item key, linked fields, history) is preserved by `CipherEditor`.
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
    @State private var accountId: String?
    /// Card / identity / SSH-key properties by API name.
    @State private var props: [String: String] = [:]
    @State private var customFields: [CustomField] = []
    @State private var showPassword = false
    @State private var showSecrets = false
    @State private var showGenerator = false
    @State private var saving = false
    @FocusState private var focus: Field?

    enum Field { case name }

    private var kind: VaultItem.Kind {
        switch mode {
        case .create(let k): k.itemKind
        case .edit(let item): item.kind
        }
    }

    /// Folders belong to one account; only offer the item's (or the chosen) account's folders.
    private var accountFolders: [Grouping] {
        let id: String? = if case .edit(let item) = mode { item.accountId } else { accountId }
        return id.flatMap { model.session(for: $0)?.folders } ?? model.folders
    }

    private var title: LocalizedStringKey {
        switch mode {
        case .create(.login): "New Login"
        case .create(.secureNote): "New Secure Note"
        case .create(.card): "New Card"
        case .create(.identity): "New Identity"
        case .create(.sshKey): "New SSH Key"
        case .edit: "Edit Item"
        }
    }

    private var symbol: String {
        switch kind {
        case .login: "key.fill"; case .note: "note.text"; case .card: "creditcard.fill"
        case .identity: "person.vcard.fill"; case .sshKey: "terminal.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(Color.brand)
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 4)
            Form {
                Section {
                    if case .create = mode, model.sessions.count > 1 {
                        Picker("Account", selection: $accountId) {
                            ForEach(model.sessions, id: \.id) { Text(verbatim: "\($0.account.email) · \($0.account.serverSummary)").tag(String?.some($0.id)) }
                        }
                        .onChange(of: accountId) { folderId = nil }
                    }
                    TextField("Name", text: $name, prompt: Text("e.g. GitHub"))
                        .focused($focus, equals: .name)
                    if !accountFolders.isEmpty {
                        Picker("Folder", selection: $folderId) {
                            Text("No Folder").tag(String?.none)
                            ForEach(accountFolders) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    }
                }

                switch kind {
                case .login: loginSection
                case .card: cardSection
                case .identity: identitySection
                case .sshKey: sshSection
                case .note: EmptyView()
                }

                customFieldsSection

                Section("Notes") {
                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(minHeight: kind == .note ? 180 : 70)
                        .scrollContentBackground(.hidden)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if kind != .login && kind != .note {
                    Toggle("Show hidden values", isOn: $showSecrets).toggleStyle(.checkbox).font(.callout)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction).buttonStyle(.appSecondary)
                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 6) {
                        if saving { ProgressView().controlSize(.small) }
                        Text("Save")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.appPrimary)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
            .padding(14)
        }
        .frame(width: 540, height: kind == .note ? 460 : 620)
        .navigationTitle(title)
        .onAppear(perform: load)
    }

    // MARK: Sections

    @ViewBuilder private var loginSection: some View {
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
                    Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye").accessibilityLabel(showPassword ? Text("Hide") : Text("Reveal")) }
                        .buttonStyle(.borderless).help(showPassword ? Text("Hide") : Text("Reveal"))
                    Button { showGenerator = true } label: { Image(systemName: "dice").accessibilityLabel(Text("Generate password")) }
                        .buttonStyle(.borderless).help(Text("Generate password"))
                        .popover(isPresented: $showGenerator, arrowEdge: .trailing) {
                            GeneratorView(modes: [.password, .passphrase], compact: true) { generated in
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

    @ViewBuilder private var cardSection: some View {
        Section {
            prop("Cardholder", "cardholderName")
            Picker("Brand", selection: binding("brand")) {
                Text("—").tag("")
                ForEach(["Visa", "Mastercard", "Amex", "Discover", "JCB", "UnionPay", "Diners Club", "Maestro", "Other"], id: \.self) {
                    Text(verbatim: $0).tag($0)
                }
            }
            prop("Card number", "number", secret: true, monospaced: true)
            HStack {
                Picker("Expires", selection: binding("expMonth")) {
                    Text("Month").tag("")
                    ForEach(1...12, id: \.self) { Text(String(format: "%02d", $0)).tag(String($0)) }
                }
                TextField("Year", text: binding("expYear"), prompt: Text(verbatim: "2030"))
                    .labelsHidden()
                    .frame(width: 70)
            }
            prop("Security code", "code", secret: true, monospaced: true)
        }
    }

    @ViewBuilder private var identitySection: some View {
        Section("Name") {
            prop("Title", "title"); prop("First name", "firstName"); prop("Middle name", "middleName"); prop("Last name", "lastName")
        }
        Section("Contact") {
            prop("Email", "email"); prop("Phone", "phone"); prop("Company", "company"); prop("Username", "username")
        }
        Section("Address") {
            prop("Address 1", "address1"); prop("Address 2", "address2"); prop("City", "city")
            prop("State / Province", "state"); prop("Postal code", "postalCode"); prop("Country", "country")
        }
        Section("Documents") {
            prop("National ID / SSN", "ssn", secret: true); prop("Passport number", "passportNumber", secret: true)
            prop("Licence number", "licenseNumber", secret: true)
        }
    }

    @ViewBuilder private var sshSection: some View {
        Section {
            LabeledContent("Private key") {
                VStack(alignment: .trailing, spacing: 6) {
                    if showSecrets || (props["privateKey"] ?? "").isEmpty {
                        TextEditor(text: binding("privateKey"))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 90)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 6))
                    } else {
                        Text(verbatim: "•••••••• OpenSSH private key ••••••••").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Button("Generate Ed25519 Key") {
                        let pair = SSHKeyPair.generateEd25519(comment: name.isEmpty ? "" : name)
                        props["privateKey"] = pair.privateKey
                        props["publicKey"] = pair.publicKey
                        props["keyFingerprint"] = pair.fingerprint
                    }
                }
            }
            prop("Public key", "publicKey", monospaced: true)
            prop("Fingerprint", "keyFingerprint", monospaced: true)
        }
    }

    @ViewBuilder private var customFieldsSection: some View {
        Section {
            ForEach($customFields) { $field in
                HStack(spacing: 8) {
                    TextField("Name", text: $field.name, prompt: Text("Name")).labelsHidden().frame(width: 130)
                    switch field.kind {
                    case .boolean:
                        Toggle("Value", isOn: Binding(get: { field.value == "true" }, set: { field.value = $0 ? "true" : "false" }))
                            .labelsHidden()
                        Spacer()
                    case .hidden where !showSecrets:
                        SecureField("Value", text: $field.value, prompt: Text("Value")).labelsHidden()
                    default:
                        TextField("Value", text: $field.value, prompt: Text("Value")).labelsHidden()
                    }
                    Picker("Type", selection: $field.kind) {
                        Text("Text").tag(CustomField.Kind.text)
                        Text("Hidden").tag(CustomField.Kind.hidden)
                        Text("Yes / No").tag(CustomField.Kind.boolean)
                    }
                    .labelsHidden()
                    .frame(width: 96)
                    Button { customFields.removeAll { $0.id == field.id } } label: { Image(systemName: "minus.circle").accessibilityLabel(Text("Remove")) }
                        .buttonStyle(.borderless).help(Text("Remove"))
                }
            }
            Button { customFields.append(CustomField(name: "", value: "", kind: .text)) } label: {
                Label("Add Field", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Custom fields")
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { props[key] ?? "" }, set: { props[key] = $0 })
    }

    @ViewBuilder
    private func prop(_ label: LocalizedStringKey, _ key: String, secret: Bool = false, monospaced: Bool = false) -> some View {
        LabeledContent(label) {
            Group {
                if secret && !showSecrets {
                    SecureField(label, text: binding(key))
                } else {
                    TextField(label, text: binding(key))
                }
            }
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
        }
    }

    // MARK: Load / save

    private func load() {
        focus = .name
        accountId = model.defaultAccountId
        guard case .edit(let item) = mode else { return }
        name = item.name
        username = item.kind == .login ? item.username ?? "" : ""
        password = item.password ?? ""
        totp = item.totpSecret ?? ""
        uri = item.uri ?? ""
        notes = item.notes ?? ""
        folderId = item.folderId
        props = item.properties
        customFields = item.customFields.filter { $0.kind != .linked }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let cleanFields = customFields.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let ok: Bool
        switch mode {
        case .create(let newKind):
            var edit = CipherEdit(name: name, notes: notes, folderId: .some(folderId))
            if newKind == .login { (edit.username, edit.password, edit.totp, edit.uri) = (username, password, totp, uri) }
            edit.properties = props.filter { !$0.value.isEmpty }
            if !cleanFields.isEmpty { edit.customFields = cleanFields }
            ok = await model.createItem(newKind, edit: edit, accountId: accountId)
        case .edit(let item):
            // Send only what changed.
            var edit = CipherEdit()
            if name != item.name { edit.name = name }
            if notes != (item.notes ?? "") { edit.notes = notes }
            if folderId != item.folderId { edit.folderId = .some(folderId) }
            if item.kind == .login {
                if username != (item.username ?? "") { edit.username = username }
                if password != (item.password ?? "") { edit.password = password }
                if totp != (item.totpSecret ?? "") { edit.totp = totp }
                if uri != (item.uri ?? "") { edit.uri = uri }
            }
            edit.properties = props.filter { item.properties[$0.key, default: ""] != $0.value }
            if cleanFields != item.customFields.filter({ $0.kind != .linked }) { edit.customFields = cleanFields }
            ok = edit == CipherEdit() ? true : await model.updateItem(item.id, edit: edit)
        }
        if ok { dismiss() }
    }
}

/// Password generator: length, character classes, look-alike avoidance, entropy meter.
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

    /// 1…4 with a label and colour; shared with the item card.
    var level: (Int, LocalizedStringKey, Color) {
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
