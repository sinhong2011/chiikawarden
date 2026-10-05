import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var code = ""
    @FocusState private var focus: Field?

    enum Field { case server, email, password, code }

    private var needsCode: Bool { if case .twoFactor = model.phase { true } else { false } }

    var body: some View {
        @Bindable var model = model
        ZStack {
            Backdrop()
            VStack(spacing: 22) {
                Image(systemName: needsCode ? "lock.badge.clock" : "lock.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.brand.gradient, in: .rect(cornerRadius: 18))
                    .shadow(color: .brand.opacity(0.4), radius: 14, y: 8)
                    .contentTransition(.symbolEffect(.replace))

                VStack(spacing: 4) {
                    Text(needsCode ? "Two-step verification" : "Unlock your vault")
                        .font(.system(.title, design: .rounded, weight: .heavy))
                        .contentTransition(.opacity)
                    Text(needsCode ? "Enter the 6-digit code from your authenticator app." : "Sign in to your Vaultwarden server.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    if needsCode {
                        TextField("Verification code", text: $code)
                            .textContentType(.oneTimeCode)
                            .focused($focus, equals: .code)
                            .font(.system(.title2, design: .monospaced, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        TextField("Server URL", text: $model.serverURL)
                            .textContentType(.URL)
                            .focused($focus, equals: .server)
                        TextField("Email", text: $model.email)
                            .textContentType(.username)
                            .focused($focus, equals: .email)
                        SecureField("Master password", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                    }
                }
                .textFieldStyle(GlassFieldStyle())

                if let message = model.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .transition(.blurReplace)
                }

                Button(action: submit) {
                    ZStack {
                        Text(needsCode ? "Verify" : "Log in").opacity(model.isBusy ? 0 : 1)
                        if model.isBusy { ProgressView().controlSize(.small).tint(.white) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy)
            }
            .padding(32)
            .frame(width: 380)
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
            .animation(.spring(duration: 0.45, bounce: 0.25), value: needsCode)
            .animation(.smooth, value: model.errorMessage)
        }
        .onAppear { focus = model.email.isEmpty ? .server : .password }
        .onChange(of: needsCode) { _, new in if new { focus = .code } }
    }

    private func submit() {
        Task {
            await model.login(password: password, twoFactorCode: needsCode ? code : nil)
            if model.isUnlocked { password = ""; code = "" }
        }
    }
}

struct GlassFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(.background.opacity(0.7), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
    }
}

/// Soft color field behind the glass, so the material has something to refract.
struct Backdrop: View {
    var body: some View {
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.6, 0.45], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: [
            Color(red: 0.62, green: 0.71, blue: 0.95), Color(red: 0.84, green: 0.88, blue: 1.0), Color(red: 0.97, green: 0.80, blue: 0.86),
            Color(red: 0.75, green: 0.80, blue: 0.98), Color(red: 0.96, green: 0.97, blue: 1.0), Color(red: 0.80, green: 0.92, blue: 0.95),
            Color(red: 0.56, green: 0.84, blue: 0.78), Color(red: 0.80, green: 0.78, blue: 0.97), Color(red: 0.66, green: 0.74, blue: 0.98),
        ])
        .ignoresSafeArea()
    }
}
