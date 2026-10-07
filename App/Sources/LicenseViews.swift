import SwiftUI

/// The launch reminder, in its own small window: it never covers the lock screen or anything the user is doing, and
/// "Continue Evaluating" (or Esc) closes it with nothing lost.
struct LicenseReminderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text("Triwarden is free to evaluate").font(.system(size: 17, weight: .semibold))
            Text("There's no time limit and every feature works. If Triwarden is useful to you, please buy a license — it keeps the project going.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                Button("Buy License…") {
                    model.license.buy()
                    close()
                }
                .buttonStyle(.appPrimary)
                .keyboardShortcut(.defaultAction)
                HStack(spacing: 8) {
                    Button("Enter License…") {
                        close()
                        model.showSettings(.license)
                    }
                    Button("Continue Evaluating") { close() }
                        .keyboardShortcut(.cancelAction)
                }
                .buttonStyle(.appSecondarySmall)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 380)
    }

    private func close() { dismissWindow(id: LicenseReminderView.windowID) }

    static let windowID = "license-reminder"
}

/// Settings › Registration: buy, paste a key, or see who it's registered to. Nothing here goes online: the key is
/// checked against its signature on this Mac.
struct LicenseSettings: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var problem: String?
    @State private var confirmRemove = false

    var body: some View {
        let license = model.license
        Form {
            if let registration = license.registration {
                Section {
                    LabeledContent("Registered to") {
                        VStack(alignment: .trailing, spacing: 2) {
                            if !registration.name.isEmpty { Text(verbatim: registration.name) }
                            if !registration.email.isEmpty { Text(verbatim: registration.email).foregroundStyle(.secondary) }
                        }
                    }
                    LabeledContent("License key") {
                        Text(verbatim: "••••" + (license.key ?? "").suffix(6)).monospaced()
                    }
                    HStack {
                        Spacer()
                        Button("Remove License…") { confirmRemove = true }
                    }
                } footer: {
                    Text("Thank you for supporting Triwarden. The same key works on all your Macs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("Triwarden is free to evaluate, with no time limit and nothing locked. A license is a one-time purchase that removes the occasional reminder and supports development.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Buy License…") { license.buy() }
                            .buttonStyle(.appPrimarySmall)
                            .disabled(license.storeURL == nil)
                    }
                } footer: {
                    Text("Pay by card, Alipay, WeChat Pay or PayPal. Building Triwarden from source yourself is always free.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    TextField("License key", text: $key, prompt: Text("Paste the key from your receipt"), axis: .vertical)
                        .lineLimit(2...4)
                        .labelsHidden()
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit(register)
                    HStack {
                        if let problem {
                            Text(problem).font(.caption).foregroundStyle(.red)
                        }
                        Spacer()
                        Button("Register", action: register)
                            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Already bought one?")
                } footer: {
                    Text("The key is checked on this Mac. Triwarden never contacts a license server.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove the license from this Mac?", isPresented: $confirmRemove) {
            Button("Remove License", role: .destructive) { license.remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Triwarden keeps working. You can register again with the same key at any time.")
        }
    }

    private func register() {
        do {
            try model.license.register(key)
            key = ""
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}
