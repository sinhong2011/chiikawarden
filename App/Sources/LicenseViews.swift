import SwiftUI

/// The launch reminder, in its own small window: it never covers the lock screen or anything the user is doing, and
/// "Not Now" (or Esc) closes it with nothing lost.
struct LicenseReminderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            if let version = model.license.updatedTo {
                Label("Updated to \(version)", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Color.primary.opacity(0.06), in: .capsule)
                    .padding(.bottom, 14)
            }
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            Text("Enjoying Triwarden?")
                .font(.system(size: 20, weight: .bold)).tracking(-0.2)
                .padding(.top, 14)
            Text("It's free to use for as long as you like, with every feature. If it's earned a place on your Mac, a license keeps it going.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            LicensePerks()
                .padding(.top, 16)
            VStack(spacing: 8) {
                Button("Buy a License") {
                    model.license.buy()
                    close()
                }
                .buttonStyle(AppButtonStyle(kind: .primary, large: true))
                .keyboardShortcut(.defaultAction)
                Button("I Have a License Key") {
                    close()
                    model.license.wantsKeyEntry = true
                    model.showSettings(.license)
                }
                .buttonStyle(AppButtonStyle(kind: .secondary, large: true))
                Button("Not Now") { close() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, 4)
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: 460)
    }

    private func close() { dismissWindow(id: LicenseReminderView.windowID) }

    static let windowID = "license-reminder"
}

/// What a license is, at a glance: three quiet chips.
private struct LicensePerks: View {
    var body: some View {
        HStack(spacing: 6) {
            perk("checkmark.circle", "One-time purchase")
            perk("laptopcomputer", "All your Macs")
            perk("lock.shield", "Nothing locked")
        }
    }

    private func perk(_ symbol: String, _ title: LocalizedStringKey) -> some View {
        Label(title, systemImage: symbol)
            .labelStyle(PerkLabelStyle())
    }

    private struct PerkLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 5) {
                configuration.icon.font(.system(size: 10, weight: .semibold))
                configuration.title.font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9).frame(height: 24)
            .background(Color.primary.opacity(0.06), in: .capsule)
        }
    }
}

/// Settings › Registration: buy, paste a key, or see who it's registered to. Only Register goes online, and only for
/// a key from a Lemon Squeezy receipt (once); an offline key is checked on this Mac.
struct LicenseSettings: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var problem: String?
    @State private var working = false
    @State private var confirmRemove = false
    @State private var justRegistered = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        let license = model.license
        Form {
            if let registration = license.registration {
                registered(registration, key: license.key ?? "")
            } else {
                unregistered(license)
            }
        }
        .formStyle(.grouped)
        .animation(.smooth(duration: 0.35), value: license.isRegistered)
        .onAppear {
            if license.wantsKeyEntry { keyFocused = true; license.wantsKeyEntry = false }
        }
        .onChange(of: license.wantsKeyEntry) { _, wants in
            if wants { keyFocused = true; license.wantsKeyEntry = false }
        }
        .confirmationDialog("Remove the license from this Mac?", isPresented: $confirmRemove) {
            Button("Remove License", role: .destructive) { license.remove(); justRegistered = false }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Triwarden keeps working. You can register again with the same key at any time.")
        }
    }

    // MARK: Not registered

    @ViewBuilder private func unregistered(_ license: License) -> some View {
        Section {
            VStack(spacing: 0) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                Text("Support Triwarden")
                    .font(.system(size: 20, weight: .bold)).tracking(-0.2)
                    .padding(.top, 10)
                Text("Every feature is free, with no time limit. A license is a one-time purchase that ends the weekly reminder and keeps the project going.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
                    .padding(.top, 4)
                LicensePerks().padding(.top, 14)
                Button("Buy a License") { license.buy() }
                    .buttonStyle(.appPrimary)
                    .disabled(license.storeURL == nil)
                    .padding(.top, 18)
                Text("Card, Alipay, WeChat Pay or PayPal")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }

        Section {
            HStack(spacing: 8) {
                TextField("License key", text: $key, prompt: Text("Paste the key from your receipt"))
                    .labelsHidden()
                    .textFieldStyle(SoftFieldStyle())
                    .font(key.isEmpty ? .system(size: 13) : .system(size: 12, design: .monospaced))
                    .focused($keyFocused)
                    .onSubmit(register)
                    .onChange(of: key) { problem = nil }
                if key.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        guard let pasted = strings.first else { return }
                        key = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        register()
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                } else {
                    Button(action: register) {
                        if working { ProgressView().controlSize(.small).frame(width: 52) } else { Text("Register") }
                    }
                    .buttonStyle(.appPrimarySmall)
                    .disabled(working)
                }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            Text("Already have a license?")
        } footer: {
            Text("A key from your receipt is confirmed with Lemon Squeezy once, when you register; nothing is checked after that. Offline keys never leave this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Registered

    @ViewBuilder private func registered(_ registration: License.Registration, key: String) -> some View {
        Section {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Color.brandFill).frame(width: 64, height: 64)
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.onBrandFill)
                        .symbolEffect(.bounce, value: justRegistered)
                }
                Text("Thank you!")
                    .font(.system(size: 20, weight: .bold)).tracking(-0.2)
                    .padding(.top, 12)
                Text(registration.name.isEmpty ? "Triwarden is registered on this Mac." : "Triwarden is registered to \(registration.name).")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }

        Section {
            if !registration.email.isEmpty {
                LabeledContent("Email") { Text(verbatim: registration.email).textSelection(.enabled) }
            }
            if !registration.order.isEmpty {
                LabeledContent("Order") { Text(verbatim: registration.order).monospacedDigit().textSelection(.enabled) }
            }
            if let date = Self.date(registration.date) {
                LabeledContent("Registered") { Text(date, format: .dateTime.day().month(.abbreviated).year()) }
            }
            LabeledContent("License key") {
                Text(verbatim: "•••• " + key.suffix(6)).font(.system(size: 12, design: .monospaced))
            }
        } footer: {
            HStack {
                Text("The same key works on all your Macs.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Remove License…", role: .destructive) { confirmRemove = true }
                    .buttonStyle(.appSecondarySmall)
            }
        }
    }

    private static func date(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601.year().month().day())
    }

    private func register() {
        guard !working, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        working = true
        problem = nil
        Task {
            do {
                try await model.license.register(key)
                key = ""
                justRegistered.toggle()
            } catch {
                withAnimation(.snappy) { problem = error.localizedDescription }
            }
            working = false
        }
    }
}
