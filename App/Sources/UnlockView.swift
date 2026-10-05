import AppKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Vault locked").font(.system(size: 26, weight: .bold)).tracking(-0.3)
                if model.accounts.count <= 1, let account = model.unlockTarget {
                    HStack(spacing: 6) {
                        Monogram(name: account.email, size: 18)
                        Text(verbatim: account.email).fontWeight(.medium)
                        Text(verbatim: "·").foregroundStyle(.tertiary)
                        Text(verbatim: account.serverSummary).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .font(.system(size: 13))
                }
            }

            if model.accounts.count > 1 {
                AccountChooser()
            }

            if model.touchIDEnabled {
                InlineTouchID()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Master password").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                PasswordField(title: "Master password", text: $password, isFocused: $focused.wrappedBinding)
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
                    Button("Log out") { model.confirmLogOut(model.unlockTarget?.id) }.buttonStyle(.link)
                }
                .font(.system(size: 12))
            }
        }
        .frame(width: 360)
        .animation(.easeOut(duration: 0.2), value: model.errorMessage)
        .onAppear {
            focused = true
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

/// Which saved account the master password is for (shown when there are several).
private struct AccountChooser: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                let selected = account.id == model.unlockTarget?.id
                Button { model.unlockTargetID = account.id; model.errorMessage = nil } label: {
                    HStack(spacing: 10) {
                        Circle().fill(AccountColor.color(index)).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: account.email).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(verbatim: account.serverSummary).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.isTouchIDEnabled(account.id) {
                            Image(systemName: "touchid").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Color.brand : Color.secondary.opacity(0.5))
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(selected ? Color.brand.opacity(0.08) : Color(nsColor: .controlBackgroundColor),
                                in: .rect(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.brand : Color(nsColor: .separatorColor), lineWidth: selected ? 1.5 : 1))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Embedded Touch ID prompt (the system's own sensor glyph) that unseals every enrolled account in place.
private struct InlineTouchID: View {
    @Environment(AppModel.self) private var model
    @State private var context = LAContext()
    @State private var attempt = 0
    @State private var prompting = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                // The system glyph only draws during a prompt; show ours otherwise.
                Image(systemName: "touchid").font(.system(size: 24)).foregroundStyle(Color.brand)
                    .opacity(prompting ? 0 : 1)
                TouchIDGlyph(context: context).opacity(prompting ? 1 : 0)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Touch ID to unlock").font(.system(size: 13, weight: .semibold))
                Text("Or enter your master password below.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { attempt += 1 } label: { Image(systemName: "arrow.clockwise").accessibilityLabel(Text("Try Touch ID again")) }
                .buttonStyle(.borderless)
                .help(Text("Try Touch ID again"))
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .task(id: attempt) {
            // A fresh context per attempt; the embedded view shows its prompt inline.
            let fresh = LAContext()
            context = fresh
            try? await Task.sleep(for: .milliseconds(150)) // let the view attach to the new context
            prompting = true
            await model.unlockWithTouchID(context: fresh)
            prompting = false
        }
    }
}

private struct TouchIDGlyph: NSViewRepresentable {
    let context: LAContext

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        install(in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // LAAuthenticationView is bound to one LAContext; swap the child when it changes.
        if (container.subviews.first as? LAAuthenticationView)?.context !== self.context { install(in: container) }
    }

    private func install(in container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        let glyph = LAAuthenticationView(context: self.context, controlSize: .large)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }
}
