import TriCrypto
import SwiftUI
import VaultwardenAPI

/// Create or edit any item type. Only changed fields are sent; everything else on the server's copy
/// (passkeys, item key, linked fields, history) is preserved by `CipherEditor`.
struct EditItemSheet: View {
    enum Mode: Equatable {
        case create(AppModel.NewItemKind)
        case edit(VaultItem)
        /// A new item filled in from an existing one (passkeys and attachments stay with the original).
        case clone(VaultItem)
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
    @State private var reprompt = false
    @State private var showSecrets = false
    @State private var showGenerator = false
    @State private var saving = false
    @FocusState private var focus: Field?

    enum Field { case name }

    private var kind: VaultItem.Kind {
        switch mode {
        case .create(let k): k.itemKind
        case .edit(let item), .clone(let item): item.kind
        }
    }

    /// Folders belong to one account; only offer the item's (or the chosen) account's folders.
    private var accountFolders: [Grouping] {
        let id: String? = switch mode { case .edit(let item), .clone(let item): item.accountId; case .create: accountId }
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
        case .clone: "Clone Item"
        }
    }

    private var symbol: String {
        switch kind {
        case .login: "key.fill"; case .note: "note.text"; case .card: "creditcard.fill"
        case .identity: "person.crop.rectangle.fill"; case .sshKey: "terminal.fill"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch kind {
        case .login: "A sign-in for a website or app."
        case .note: "Private text, encrypted like everything else."
        case .card: "A payment card, ready for AutoFill."
        case .identity: "Your details, for filling in forms."
        case .sshKey: "A key the Triwarden SSH agent can sign with."
        }
    }

    /// Secrets on cards, identities and SSH keys hide until asked for.
    private var hasHiddenValues: Bool { kind == .card || kind == .identity || kind == .sshKey }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FormHeader(symbol: symbol, title: title, subtitle: subtitle)

                    FormCard {
                        if case .create = mode, model.sessions.count > 1 {
                            FormField(label: "Account") {
                                SoftMenu(options: model.sessions.map { (String?.some($0.id), "\($0.account.email) · \($0.account.serverSummary)") },
                                         selection: $accountId, accessibilityLabel: "Account")
                            }
                            .onChange(of: accountId) { folderId = nil }
                        }
                        FormField(label: "Name") {
                            TextField("Name", text: $name, prompt: Text("e.g. GitHub"))
                                .textFieldStyle(SoftFieldStyle())
                                .focused($focus, equals: .name)
                        }
                        if !accountFolders.isEmpty {
                            FormField(label: "Folder") {
                                FolderCascader(folders: accountFolders, selection: $folderId)
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

                    FormCard(title: "Notes") {
                        SoftEditor(text: $notes, minHeight: kind == .note ? 200 : 80)
                    }

                    FormCard {
                        Toggle(isOn: $reprompt) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ask for master password").font(.system(size: 13))
                                Text("Before showing or copying this item's secrets.").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.trailingSwitch)
                    }
                }
                .padding(20)
            }
            .thinScroller()

            FormFooter(action: "Save", busy: saving, disabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
                       cancel: { dismiss() }, submit: { Task { await save() } }) {
                if hasHiddenValues {
                    Toggle("Show hidden values", isOn: $showSecrets).toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
                }
            }
        }
        .frame(width: 580, height: kind == .note ? 560 : 700)
        .background(Color.windowBase)
        .navigationTitle(title)
        .onAppear(perform: load)
    }

    // MARK: Sections

    @ViewBuilder private var loginSection: some View {
        FormCard(title: "Sign-in") {
            FormField(label: "Username") {
                TextField("Username", text: $username, prompt: Text(verbatim: "you@example.com"))
                    .textFieldStyle(SoftFieldStyle())
                    .textContentType(.username)
            }
            FormField(label: "Password") {
                HStack(spacing: 8) {
                    PasswordField(title: "Password", text: $password, prompt: Text("Password"))
                        .font(.system(size: 13, design: .monospaced))
                    Button { showGenerator = true } label: {
                        Image(systemName: "dice").font(.system(size: 14, weight: .medium))
                            .frame(width: 38, height: 38)
                            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Generate password"))
                    .accessibilityLabel(Text("Generate password"))
                    .popover(isPresented: $showGenerator, arrowEdge: .trailing) {
                        GeneratorView(modes: [.password, .passphrase], compact: true) { generated in
                            password = generated
                            showGenerator = false
                        }
                    }
                }
                if !password.isEmpty { StrengthMeter(password: password).padding(.top, 2) }
            }
            FormField(label: "Website") {
                TextField("Website", text: $uri, prompt: Text(verbatim: "https://example.com"))
                    .textFieldStyle(SoftFieldStyle())
                    .textContentType(.URL)
            }
            FormField(label: "One-time code secret", note: "From the site's two-factor setup: an otpauth:// link or the key under the QR code.") {
                TextField("One-time code secret", text: $totp, prompt: Text("otpauth://… or base32 key"))
                    .textFieldStyle(SoftFieldStyle())
                    .font(.system(size: 13, design: .monospaced))
                if !totp.isEmpty, TOTP(totp) == nil {
                    Label("That doesn't look like a valid one-time code secret.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder private var cardSection: some View {
        FormCard(title: "Card") {
            prop("Cardholder", "cardholderName")
            FormField(label: "Brand") {
                SoftMenu(options: [("", "—")] + ["Visa", "Mastercard", "Amex", "Discover", "JCB", "UnionPay", "Diners Club", "Maestro", "Other"].map { ($0, $0) },
                         selection: binding("brand"), accessibilityLabel: "Brand")
            }
            prop("Card number", "number", secret: true, monospaced: true)
            HStack(alignment: .top, spacing: 12) {
                FormField(label: "Expires") {
                    HStack(spacing: 8) {
                        SoftMenu(options: (1...12).map { (String($0), String(format: "%02d", $0)) }, selection: binding("expMonth"),
                                 placeholder: "Month", accessibilityLabel: "Expiry month")
                        TextField("Year", text: binding("expYear"), prompt: Text(verbatim: "2030"))
                            .textFieldStyle(SoftFieldStyle())
                            .frame(width: 90)
                    }
                }
                prop("Security code", "code", secret: true, monospaced: true)
                    .frame(width: 150)
            }
        }
    }

    @ViewBuilder private var identitySection: some View {
        FormCard(title: "Name") {
            pair(("Title", "title"), ("First name", "firstName"))
            pair(("Middle name", "middleName"), ("Last name", "lastName"))
        }
        FormCard(title: "Contact") {
            pair(("Email", "email"), ("Phone", "phone"))
            pair(("Company", "company"), ("Username", "username"))
        }
        FormCard(title: "Address") {
            prop("Address 1", "address1"); prop("Address 2", "address2")
            pair(("City", "city"), ("State / Province", "state"))
            pair(("Postal code", "postalCode"), ("Country", "country"))
        }
        FormCard(title: "Documents") {
            prop("National ID / SSN", "ssn", secret: true)
            pair(("Passport number", "passportNumber"), ("Licence number", "licenseNumber"), secret: true)
        }
    }

    @ViewBuilder private var sshSection: some View {
        FormCard(title: "Key") {
            FormField(label: "Private key") {
                if showSecrets || (props["privateKey"] ?? "").isEmpty {
                    SoftEditor(text: binding("privateKey"), minHeight: 100, monospaced: true)
                } else {
                    Text(verbatim: "•••••••• OpenSSH private key ••••••••")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
                }
                Button("Generate Ed25519 Key", systemImage: "wand.and.stars") {
                    let pair = SSHKeyPair.generateEd25519(comment: name.isEmpty ? "" : name)
                    props["privateKey"] = pair.privateKey
                    props["publicKey"] = pair.publicKey
                    props["keyFingerprint"] = pair.fingerprint
                }
                .buttonStyle(.appSecondary)
                .padding(.top, 2)
            }
            prop("Public key", "publicKey", monospaced: true)
            prop("Fingerprint", "keyFingerprint", monospaced: true)
        }
    }

    @ViewBuilder private var customFieldsSection: some View {
        FormCard(title: "Custom fields") {
            ForEach($customFields) { $field in
                HStack(spacing: 8) {
                    TextField("Name", text: $field.name, prompt: Text("Name"))
                        .textFieldStyle(SoftFieldStyle()).frame(width: 130)
                    Group {
                        switch field.kind {
                        case .boolean:
                            Toggle("Value", isOn: Binding(get: { field.value == "true" }, set: { field.value = $0 ? "true" : "false" }))
                                .labelsHidden().toggleStyle(.switch)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .hidden where !showSecrets:
                            SecureField("Value", text: $field.value, prompt: Text("Value")).textFieldStyle(SoftFieldStyle())
                        default:
                            TextField("Value", text: $field.value, prompt: Text("Value")).textFieldStyle(SoftFieldStyle())
                        }
                    }
                    SoftMenu(options: [(CustomField.Kind.text, String(localized: "Text")), (.hidden, String(localized: "Hidden")),
                                       (.boolean, String(localized: "Yes / No"))],
                             selection: $field.kind, accessibilityLabel: "Type")
                        .frame(width: 110)
                    Button { withAnimation(.snappy) { customFields.removeAll { $0.id == field.id } } } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 15)).foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Remove"))
                    }
                    .buttonStyle(.plain).help(Text("Remove"))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Button {
                withAnimation(.snappy) { customFields.append(CustomField(name: "", value: "", kind: .text)) }
            } label: {
                Label("Add Field", systemImage: "plus")
            }
            .buttonStyle(.appSecondary)
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { props[key] ?? "" }, set: { props[key] = $0 })
    }

    @ViewBuilder
    private func prop(_ label: LocalizedStringKey, _ key: String, secret: Bool = false, monospaced: Bool = false) -> some View {
        FormField(label: label) {
            Group {
                if secret && !showSecrets {
                    SecureField(label, text: binding(key), prompt: Text(verbatim: ""))
                } else {
                    TextField(label, text: binding(key), prompt: Text(verbatim: ""))
                }
            }
            .textFieldStyle(SoftFieldStyle())
            .font(.system(size: 13, design: monospaced ? .monospaced : .default))
        }
    }

    /// Two short fields side by side.
    private func pair(_ a: (LocalizedStringKey, String), _ b: (LocalizedStringKey, String), secret: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            prop(a.0, a.1, secret: secret)
            prop(b.0, b.1, secret: secret)
        }
    }

    // MARK: Load / save

    private func load() {
        focus = .name
        accountId = model.defaultAccountId
        let source: VaultItem
        switch mode {
        case .create: return
        case .edit(let item): source = item
        case .clone(let item): source = item
        }
        let item = source
        name = item.name
        username = item.kind == .login ? item.username ?? "" : ""
        password = item.password ?? ""
        totp = item.totpSecret ?? ""
        uri = item.uri ?? ""
        notes = item.notes ?? ""
        folderId = item.folderId
        props = item.properties
        customFields = item.customFields.filter { $0.kind != .linked }
        reprompt = item.reprompt
        if case .clone = mode {
            name = String(localized: "\(item.name) - Clone")
            accountId = item.accountId
            if item.organizationId != nil { folderId = nil } // the copy is personal
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let cleanFields = customFields.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let ok: Bool
        switch mode {
        case .create, .clone:
            let newKind: AppModel.NewItemKind = if case .create(let k) = mode { k } else { AppModel.NewItemKind(kind) }
            var edit = CipherEdit(name: name, notes: notes, folderId: .some(folderId))
            edit.reprompt = reprompt
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
            if reprompt != item.reprompt { edit.reprompt = reprompt }
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
