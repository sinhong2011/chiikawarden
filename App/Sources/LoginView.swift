import AppKit
import SwiftUI

/// Login: a dark brand stage on the left, a calm native form on the right.
/// The stage bleeds to the window edge so the traffic lights sit on it, and hides on narrow windows.
struct LoginView: View {
    var body: some View {
        GeometryReader { geo in
            let showStage = geo.size.width >= 820
            HStack(spacing: 0) {
                if showStage {
                    BrandStage()
                        .frame(width: min(max(geo.size.width * 0.46, 380), 560))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ScrollView {
                    LoginForm()
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .animation(.snappy(duration: 0.3), value: showStage)
        }
        .ignoresSafeArea()
    }
}

private struct LoginForm: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var code = ""
    @AppStorage("rememberEmail") private var rememberEmail = true
    @FocusState private var focus: Field?

    enum Field { case server, email, password, code }
    private enum Step: Equatable { case credentials, authenticator, emailCode }

    private var step: Step {
        switch model.phase {
        case .twoFactor: .authenticator
        case .deviceVerification: .emailCode
        default: .credentials
        }
    }

    private var title: LocalizedStringKey {
        switch step {
        case .credentials: "Welcome back"
        case .authenticator: "Two-step verification"
        case .emailCode: "Verify this Mac"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch step {
        case .credentials: "Choose where your vault lives."
        case .authenticator: "Enter the 6-digit code from your authenticator app."
        case .emailCode: "Bitwarden emailed a verification code to \(model.email)."
        }
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable().frame(width: 22, height: 22)
                    Text(verbatim: "Chiikawarden").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)
                Text(title).font(.system(size: 26, weight: .bold)).tracking(-0.3)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }

            if step == .credentials {
                ServerPicker(selection: $model.serverKind)

                VStack(alignment: .leading, spacing: 14) {
                    if model.serverKind == .selfHosted {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledField("Server URL") {
                                TextField("Server URL", text: $model.serverURL, prompt: Text(verbatim: "https://vault.example.com"))
                                    .textContentType(.URL)
                                    .focused($focus, equals: .server)
                            }
                            CustomEnvironmentFields()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    LabeledField("Email") {
                        TextField("Email", text: $model.email, prompt: Text(verbatim: "you@example.com"))
                            .textContentType(.username)
                            .focused($focus, equals: .email)
                    }
                    LabeledField("Master password", accessory: { ForgotPasswordButton(email: model.email) }) {
                        SecureField("Master password", text: $password, prompt: Text(verbatim: ""))
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                    }
                }
                .textFieldStyle(SoftFieldStyle())

                HStack {
                    ServerStatusLine(status: model.serverStatus)
                    Spacer()
                    Toggle("Remember email", isOn: $rememberEmail)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
            } else {
                TextField("Verification code", text: $code, prompt: Text(verbatim: "123 456"))
                    .textFieldStyle(SoftFieldStyle(height: 52))
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textContentType(.oneTimeCode)
                    .focused($focus, equals: .code)
            }

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            VStack(spacing: 10) {
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if model.isBusy { ProgressView().controlSize(.small).tint(.white) }
                        Text(step == .credentials ? "Log in" : "Verify").font(.system(size: 14, weight: .semibold))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy)

                if step != .credentials {
                    Button("Back") { code = ""; model.cancelChallenge() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                } else if model.addingAccount {
                    Button("Cancel") { model.cancelAddAccount() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.top, 4)
        }
        .frame(width: 360)
        .animation(.snappy(duration: 0.25), value: step)
        .animation(.snappy(duration: 0.25), value: model.serverKind)
        .animation(.easeOut(duration: 0.2), value: model.errorMessage)
        .onAppear {
            focus = model.email.isEmpty ? .email : .password
            model.checkServer()
        }
        .onChange(of: model.serverKind) { model.checkServer() }
        .onChange(of: model.serverURL) { model.checkServer() }
        .onChange(of: step) { _, new in if new != .credentials { code = ""; focus = .code } }
    }

    private func submit() {
        Task {
            await model.login(password: password, code: step == .credentials ? nil : code)
            if model.isUnlocked {
                password = ""
                code = ""
                if !rememberEmail { UserDefaults.standard.removeObject(forKey: "email") }
            }
        }
    }
}

/// Full-width brand button with a gentle press.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 40)
            // Fixed deep blue in both appearances so white text keeps ≥4.5:1 contrast.
            .background(Color(nsColor: .chiikawardenBrand).opacity(isEnabled ? 1 : 0.5), in: .rect(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .shadow(color: Color.brand.opacity(configuration.isPressed ? 0.15 : 0.3), radius: configuration.isPressed ? 3 : 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Quiet filled field: subtle fill, hairline border, accent ring on focus.
struct SoftFieldStyle: TextFieldStyle {
    var height: CGFloat = 38
    @FocusState private var focused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(focused ? Color.brand : Color(nsColor: .separatorColor), lineWidth: focused ? 1.5 : 1)
            )
            .shadow(color: focused ? Color.brand.opacity(0.18) : .clear, radius: 4)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

private struct LabeledField<Accessory: View, Content: View>: View {
    let label: LocalizedStringKey
    let accessory: Accessory
    let content: Content

    init(_ label: LocalizedStringKey, @ViewBuilder accessory: () -> Accessory = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.label = label
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                accessory
            }
            content.labelsHidden()
        }
    }
}

/// "Forgot?" → explains master passwords can't be reset, and offers to send the hint.
private struct ForgotPasswordButton: View {
    @Environment(AppModel.self) private var model
    let email: String
    @State private var isPresented = false

    var body: some View {
        Button("Forgot password?") { isPresented = true }
            .buttonStyle(.link)
            .font(.system(size: 12))
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                PasswordHintView(email: email)
                    .environment(model)
            }
    }
}

private struct PasswordHintView: View {
    @Environment(AppModel.self) private var model
    @State var email: String
    @State private var state: HintState = .idle

    enum HintState: Equatable { case idle, sending, sent, revealed(String), failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Master password hint", systemImage: "questionmark.key.filled")
                .font(.system(size: 14, weight: .semibold))
            Text("Your master password can't be recovered — not even by the server. If you set a hint, we can email it to you.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Email", text: $email, prompt: Text(verbatim: "you@example.com"))
                .textFieldStyle(SoftFieldStyle(height: 34))
            switch state {
            case .sent:
                Label("If this account has a hint, it's on its way to your inbox.", systemImage: "paperplane.fill")
                    .font(.system(size: 12)).foregroundStyle(.green)
            case .revealed(let hint):
                Label { Text(verbatim: hint).textSelection(.enabled) } icon: { Image(systemName: "lightbulb.fill") }
                    .font(.system(size: 13, weight: .medium))
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(.red)
            default:
                EmptyView()
            }
            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 8) {
                    if state == .sending { ProgressView().controlSize(.small).tint(.white) }
                    Text("Send hint").font(.system(size: 13, weight: .semibold))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(email.isEmpty || state == .sending)
        }
        .padding(18)
        .frame(width: 300)
        .animation(.snappy, value: state)
    }

    private func send() async {
        state = .sending
        switch await model.requestPasswordHint(email: email) {
        case .success(let hint?): state = .revealed(hint)
        case .success(nil): state = .sent
        case .failure(let message): state = .failed(message)
        }
    }
}

private struct ServerStatusLine: View {
    let status: AppModel.ServerStatus

    var body: some View {
        HStack(spacing: 8) {
            switch status {
            case .unknown:
                Circle().fill(.quaternary).frame(width: 7, height: 7)
                Text("Enter your server address").foregroundStyle(.secondary)
            case .checking:
                ProgressView().controlSize(.mini)
                Text("Checking server…").foregroundStyle(.secondary)
            case .reachable(let product, let version):
                Circle().fill(.green).frame(width: 7, height: 7)
                Text(verbatim: [product, version].compactMap { $0 }.joined(separator: " "))
                Text("· reachable").foregroundStyle(.secondary)
            case .unreachable(let message):
                Circle().fill(.orange).frame(width: 7, height: 7)
                Text(verbatim: message).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .animation(.easeOut(duration: 0.15), value: status)
    }
}

/// "Custom environment": per-service URLs for self-hosted servers. Empty fields derive from the server URL.
private struct CustomEnvironmentFields: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Custom environment")
                    if model.hasCustomURLs && !expanded {
                        Text("· in use").foregroundStyle(Color.brand)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Only if your services live on different URLs. Leave empty to use the server URL.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    row("Web vault", $model.customWebVault, derived(""))
                    row("API", $model.customAPI, derived("/api"))
                    row("Identity", $model.customIdentity, derived("/identity"))
                    row("Icons", $model.customIcons, derived("/icons"))
                    row("Notifications", $model.customNotifications, derived("/notifications"))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let problem = model.serverURLProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .onAppear { expanded = model.hasCustomURLs }
    }

    /// What an empty field will use: the server URL (or web vault) plus the service path.
    private func derived(_ suffix: String) -> String {
        let root = AppModel.parseURL(model.customWebVault.isEmpty ? model.serverURL : model.serverURL.isEmpty ? model.customWebVault : model.serverURL)
        return root.map { $0.absoluteString + suffix } ?? String(localized: "Server URL") + suffix
    }

    private func row(_ label: LocalizedStringKey, _ text: Binding<String>, _ placeholder: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
            TextField(label, text: text, prompt: Text(verbatim: placeholder).foregroundStyle(.tertiary))
                .textFieldStyle(SoftFieldStyle(height: 30))
                .font(.system(size: 12))
                .labelsHidden()
                .textContentType(.URL)
        }
    }
}
