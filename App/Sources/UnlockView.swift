import AppKit
import SwiftUI

/// Signed in, vault locked: Touch ID first, master password as fallback. Works offline.
struct UnlockView: View {
    var body: some View {
        GeometryReader { geo in
            let showStage = geo.size.width >= 820
            HStack(spacing: 0) {
                if showStage {
                    BrandStage()
                        .frame(width: min(max(geo.size.width * 0.46, 380), 560))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                UnlockForm()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.snappy(duration: 0.3), value: showStage)
        }
        .ignoresSafeArea()
    }
}

private struct UnlockForm: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var shake = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 22, height: 22)
                Text(verbatim: "Chiikawarden").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Vault locked").font(.system(size: 26, weight: .bold)).tracking(-0.3)
                HStack(spacing: 6) {
                    Monogram(name: model.email, size: 18)
                    Text(verbatim: model.email).fontWeight(.medium)
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                    Text(verbatim: model.serverSummary).foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.system(size: 13))
            }

            if model.touchIDEnabled {
                Button { Task { await model.unlockWithTouchID() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "touchid").font(.system(size: 22, weight: .regular)).foregroundStyle(Color.brand)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Unlock with Touch ID").font(.system(size: 13, weight: .semibold))
                            Text("Or enter your master password below.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Master password").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                SecureField("Master password", text: $password, prompt: Text(verbatim: ""))
                    .textFieldStyle(SoftFieldStyle())
                    .textContentType(.password)
                    .focused($focused)
                    .labelsHidden()
                    .modifier(Shake(trigger: shake))
            }

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(.red).transition(.opacity)
            }

            VStack(spacing: 12) {
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if model.isBusy { ProgressView().controlSize(.small).tint(.white) }
                        Text("Unlock").font(.system(size: 14, weight: .semibold))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy || password.isEmpty)

                HStack(spacing: 4) {
                    Text("Not you?").foregroundStyle(.secondary)
                    Button("Log out") { model.logOut() }.buttonStyle(.link)
                }
                .font(.system(size: 12))
            }
        }
        .frame(width: 360)
        .animation(.easeOut(duration: 0.2), value: model.errorMessage)
        .onAppear {
            focused = true
            if model.touchIDEnabled { Task { await model.unlockWithTouchID() } }
        }
    }

    private func submit() {
        Task {
            await model.unlock(password: password)
            if model.isUnlocked { password = "" } else { withAnimation(.default) { shake += 1 } }
        }
    }
}

/// Small horizontal shake for a wrong password.
private struct Shake: GeometryEffect {
    var trigger: Int
    var animatableData: CGFloat {
        get { CGFloat(trigger) }
        set { progress = newValue }
    }
    private var progress: CGFloat = 0
    init(trigger: Int) { self.trigger = trigger; progress = CGFloat(trigger) }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(progress * .pi * 6), y: 0))
    }
}
