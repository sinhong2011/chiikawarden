import AppKit
import AuthenticationServices
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Settings with a sidebar, like System Settings: sections on the left, the chosen page on the right.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, accounts, accountSecurity, emergency, security, developer, server, about
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .accounts: "Accounts"
            case .accountSecurity: "Account Security"
            case .emergency: "Emergency Access"
            case .security: "Security"
            case .developer: "Developer"
            case .server: "Server"
            case .about: "About"
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .accounts: "person.2"
            case .accountSecurity: "person.badge.shield.checkmark"
            case .emergency: "cross.case"
            case .security: "lock.shield"
            case .developer: "terminal"
            case .server: "server.rack"
            case .about: "info.circle"
            }
        }
    }

    @AppStorage("settingsPane") private var paneRaw = Pane.general.rawValue
    private var pane: Binding<Pane?> {
        Binding(get: { Pane(rawValue: paneRaw) ?? .general }, set: { paneRaw = ($0 ?? .general).rawValue })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: pane) {
                ForEach(Pane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbol).tag(pane)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            Group {
                switch pane.wrappedValue ?? .general {
                case .general: GeneralSettings()
                case .accounts: AccountsSettings()
                case .accountSecurity: AccountSecuritySettings()
                case .emergency: EmergencyAccessSettings()
                case .security: SecuritySettings()
                case .developer: DeveloperSettings()
                case .server: ServerSettings()
                case .about: AboutSettings()
                }
            }
            .navigationTitle(pane.wrappedValue?.title ?? "General")
            // Every pane's buttons in the app's capsule style (explicit styles, like links, still win).
            .buttonStyle(.appSecondarySmall)
        }
        // Opens roomy and resizes freely; forms scroll when the window is shorter than their content.
        .frame(minWidth: 680, idealWidth: 820, maxWidth: .infinity, minHeight: 460, idealHeight: 640, maxHeight: .infinity)
    }
}

// MARK: General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.appearance) private var appearance = "system"
    @State private var autoFillOn: Bool?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)

                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(verbatim: loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                @Bindable var updates = model.updates
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                    .disabled(!updates.isConfigured)
                Toggle("Download and install updates automatically", isOn: $updates.automaticallyDownloads)
                    .disabled(!updates.isConfigured || !updates.automaticallyChecks)
                LabeledContent {
                    Button("Check Now") { updates.checkForUpdates() }
                        .disabled(!updates.canCheck)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(updates.current)")
                        if !updates.isConfigured {
                            Text("Updates are off in development builds.").font(.caption).foregroundStyle(.secondary)
                        } else if let checked = updates.lastChecked {
                            Text("Last checked \(checked, format: .relative(presentation: .named))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Updates come from this project's GitHub releases. Each one is signed; Chiikawarden checks the signature and Apple's notarization before installing, then relaunches.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Command palette") { ShortcutRecorder() }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Works in every app. A common shortcut like ⌘K is taken from other apps while Chiikawarden runs; pick another if you need it elsewhere. ⌘K and ⌘F always open the palette inside the vault window.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("AutoFill") {
                    HStack(spacing: 10) {
                        if let autoFillOn {
                            Label(autoFillOn ? "On" : "Off", systemImage: autoFillOn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(autoFillOn ? .green : .secondary)
                        }
                        Button(autoFillOn == true ? "Settings…" : "Turn On…") {
                            ASSettingsHelper.openCredentialProviderAppSettings { _ in }
                        }
                    }
                }
            } footer: {
                Text("Fill passwords and verification codes in Safari, Chrome and apps. Turn on Chiikawarden in System Settings › General › AutoFill & Passwords.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .task {
                autoFillOn = await ASCredentialIdentityStore.shared.state().isEnabled
                if autoFillOn == true { AutoFillIdentities.publish(model.items, equivalents: model.equivalentDomains) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { autoFillOn = await ASCredentialIdentityStore.shared.state().isEnabled }
            }

            Section {
                Toggle("Show website icons", isOn: Binding(
                    get: { IconStore.enabled },
                    set: { on in
                        UserDefaults.standard.set(on, forKey: Pref.showIcons)
                        if !on { IconStore.shared.clear() }
                    }))
            } footer: {
                Text("Icons come from your own server (or Bitwarden for bitwarden.com accounts), so no one else learns which sites you use. Cached icons are encrypted.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LanguagePicker()
            } footer: {
                Text("Chiikawarden is available in English, 繁體中文, 繁體中文（香港）, 简体中文 and 日本語. The AutoFill panel follows the system's language.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Security

private struct SecuritySettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.autoLockMinutes) private var autoLockMinutes = 15
    @AppStorage(Pref.lockOnSleep) private var lockOnSleep = true
    @AppStorage(Pref.lockAnimations) private var lockAnimations = true
    @AppStorage(Pref.clipboardSeconds) private var clipboardSeconds = 30

    var body: some View {
        Form {
            Section {
                Picker("Lock after inactivity", selection: $autoLockMinutes) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Divider()
                    Text("Never").tag(0)
                }
                Toggle("Lock when the Mac sleeps or the screen locks", isOn: $lockOnSleep)
                Toggle("Animate the vault door", isOn: $lockAnimations)
            } header: {
                Text("Vault")
            } footer: {
                Text("When off, the lock screen stays still and the vault opens and locks at once.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Clear copied items after", selection: $clipboardSeconds) {
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Divider()
                    Text("Never").tag(0)
                }
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Copied secrets are marked as concealed, so clipboard managers skip them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: SSH

private struct DeveloperSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.sshAgent) private var enabled = false
    @AppStorage(Pref.sshApprovalSeconds) private var approvalSeconds = 0
    @AppStorage(Pref.cli) private var cliEnabled = false
    @AppStorage(Pref.cliApprovalSeconds) private var cliApprovalSeconds = 0
    @AppStorage(Pref.browser) private var browserEnabled = false

    private var installCommand: String { "sudo ln -sf \"\(CLIBridge.toolPath)\" /usr/local/bin/cw" }

    private var configLine: String { "Host *\n  IdentityAgent \"\(model.sshAgent.socketPath)\"" }

    var body: some View {
        let agent = model.sshAgent!
        Form {
            Section {
                Toggle("Use Chiikawarden as SSH agent", isOn: $enabled)
                    .onChange(of: enabled) { _, on in on ? agent.start() : agent.stop() }
                Picker("Ask before signing", selection: $approvalSeconds) {
                    Text("Every time").tag(0)
                    Text("Once per minute, per app").tag(60)
                    Text("Once per 10 minutes, per app").tag(600)
                }
                if let error = agent.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                }
            } header: {
                Text("SSH agent")
            } footer: {
                Text("SSH key items from unlocked accounts are offered to ssh and git. Every signature needs Touch ID or your Mac password; keys never leave the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Add to ~/.ssh/config") {
                    Button("Copy") { model.copyPlain(configLine) }
                }
                Text(verbatim: configLine)
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .foregroundStyle(.secondary)
                LabeledContent("Or for one shell") {
                    Button("Copy") { model.copyPlain("export SSH_AUTH_SOCK=\"\(agent.socketPath)\"") }
                }
            } header: {
                Text("SSH setup")
            }

            Section {
                Toggle("Answer the cw command", isOn: $cliEnabled)
                    .onChange(of: cliEnabled) { model.cli.refreshRunning() }
                Picker("Ask before revealing", selection: $cliApprovalSeconds) {
                    Text("Every time").tag(0)
                    Text("Once per minute, per app").tag(60)
                    Text("Once per 10 minutes, per app").tag(600)
                }
                LabeledContent("Install cw") {
                    Button("Copy Command") { model.copyPlain(installCommand) }
                }
                Text(verbatim: installCommand)
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary)
                if let error = model.cli.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                }
            } header: {
                Text("Command line")
            } footer: {
                Text("cw get github · cw code github · cw list · cw generate. Reading anything from the vault needs it unlocked and Touch ID or your Mac password.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Allow the browser extension", isOn: $browserEnabled)
                    .onChange(of: browserEnabled) { model.cli.refreshRunning() }
                LabeledContent("Safari") {
                    Button("Open Safari Extensions") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Safari-Extensions-Settings")!)
                    }
                }
                LabeledContent("Chrome, Edge, Brave") {
                    Button("Show Extension Folder") {
                        let folder = Bundle.main.bundleURL.appending(path: "Contents/PlugIns/ChiikawardenSafari.appex/Contents/Resources/manifest.json")
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                }
            } header: {
                Text("Browser extension")
            } footer: {
                Text("Safari: turn on Chiikawarden in Safari › Settings › Extensions. Chromium browsers: load the folder as an unpacked extension, then run cw install-chrome <extension id>. Suggestions show names only; filling asks for Touch ID, saving asks you first.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !agent.recent.isEmpty {
                Section("Recent SSH requests") {
                    ForEach(Array(agent.recent.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Image(systemName: entry.allowed ? "checkmark.circle" : "xmark.circle")
                                .foregroundStyle(entry.allowed ? .green : .red)
                            Text(verbatim: "\(entry.program) → \(entry.key)")
                            Spacer()
                            Text(entry.date, style: .relative).foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Accounts

private struct AccountsSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var confirmLogOut: SavedAccount?

    var body: some View {
        Form {
            Section {
                if model.accounts.isEmpty {
                    Text("No accounts yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                    let unlocked = model.isUnlocked(account.id)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle().fill(AccountColor.color(index)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: account.email).fontWeight(.semibold)
                                Text(verbatim: account.serverSummary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label(unlocked ? "Unlocked" : "Locked", systemImage: unlocked ? "lock.open" : "lock")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Toggle("Unlock with Touch ID", isOn: Binding(
                                get: { model.isTouchIDEnabled(account.id) },
                                set: { model.setTouchID($0, for: account.id) }))
                                .disabled(!AccountStore.isTouchIDAvailable || (!unlocked && !model.isTouchIDEnabled(account.id)))
                            Spacer()
                            if unlocked {
                                Button("Export…") { model.beginExport(accountId: account.id) }
                                    .help(Text("Export this account's vault"))
                                Button("Lock") { model.lock(account.id) }
                            }
                            Button("Log Out…", role: .destructive) { confirmLogOut = account }
                        }
                        .font(.callout)
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text(AccountStore.isTouchIDAvailable
                     ? "Touch ID seals each account's key in the Secure Enclave. Unlock an account once to turn it on; one touch then opens every account that has it."
                     : "This Mac has no Touch ID available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Add Account…") {
                        model.beginAddAccount()
                        NSApp.activate()
                        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Log out of \(confirmLogOut?.email ?? "")?", isPresented: Binding(
            get: { confirmLogOut != nil }, set: { if !$0 { confirmLogOut = nil } })) {
            Button("Log Out", role: .destructive) {
                if let id = confirmLogOut?.id { model.logOut(id) }
            }
        } message: {
            Text("This removes the account and its saved vault from this Mac. Your data stays on the server.")
        }
    }
}

/// Stable colour per account position, used for dots in the sidebar and lists.
enum AccountColor {
    static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]
    static func color(_ index: Int) -> Color { palette[index % palette.count] }
}

// MARK: Server

private struct ServerSettings: View {
    @Environment(AppModel.self) private var model
    @State private var headers: [CustomHeader] = HeaderStore.load()
    @State private var cas: [Data] = Connection.trustedCAs
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        Form {
            Section {
                if cas.isEmpty {
                    Text("Using the system's trusted certificates.").foregroundStyle(.secondary)
                }
                ForEach(Array(cas.enumerated()), id: \.offset) { index, data in
                    HStack {
                        Image(systemName: "checkmark.seal").foregroundStyle(.green)
                        Text(verbatim: certificateName(data))
                        Spacer()
                        Button(role: .destructive) { cas.remove(at: index); saveCAs() } label: { Image(systemName: "minus.circle").accessibilityLabel(Text("Remove")) }
                            .buttonStyle(.borderless)
                            .help(Text("Remove"))
                    }
                }
                HStack {
                    Spacer()
                    Button("Add Certificate…") { importing = true }
                }
                if let importError { Text(verbatim: importError).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("Trusted certificates")
            } footer: {
                Text("Add your own CA if your server uses a private or self-signed certificate (PEM or DER).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach($headers) { $header in
                    HStack {
                        TextField("Name", text: $header.name, prompt: Text(verbatim: "CF-Access-Client-Id"))
                        PasswordField(title: "Value", text: $header.value, look: .plain, prompt: Text("Value"))
                        Button(role: .destructive) { headers.removeAll { $0.id == header.id } } label: { Image(systemName: "minus.circle").accessibilityLabel(Text("Remove")) }
                            .buttonStyle(.borderless)
                            .help(Text("Remove"))
                    }
                    .labelsHidden()
                }
                HStack {
                    Spacer()
                    Button("Add Header") { headers.append(CustomHeader(name: "", value: "")) }
                }
            } header: {
                Text("Extra request headers")
            } footer: {
                Text("Sent with every request, e.g. Cloudflare Access service tokens. Stored in your Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: headers) { _, new in HeaderStore.save(new); model.resetClient() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.x509Certificate, UTType(filenameExtension: "pem") ?? .data, .data]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard certificate(from: data) != nil else {
                    importError = String(localized: "That file isn't a certificate.")
                    return
                }
                cas.append(data)
                saveCAs()
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func saveCAs() {
        Connection.trustedCAs = cas
        model.resetClient()
    }

    private func certificate(from data: Data) -> SecCertificate? {
        if let c = SecCertificateCreateWithData(nil, data as CFData) { return c }
        let body = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }.joined()
        return Data(base64Encoded: body).flatMap { SecCertificateCreateWithData(nil, $0 as CFData) }
    }

    private func certificateName(_ data: Data) -> String {
        certificate(from: data).flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? "Certificate"
    }
}

// MARK: About

private struct AboutSettings: View {
    @State private var showingNotices = false

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
            Text(verbatim: "Chiikawarden").font(.system(size: 22, weight: .bold))
            Text(verbatim: "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                .foregroundStyle(.secondary)
            Text("A native Mac client for Vaultwarden and Bitwarden.")
                .padding(.top, 4)
            Text("Free software under the GNU General Public License v3.0. Not affiliated with Bitwarden, Inc. or the Vaultwarden project.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 8)
            HStack(spacing: 8) {
                Link(destination: URL(string: "https://github.com/sinhong2011/chiikawarden")!) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.appSecondarySmall)
                Link(destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!) {
                    Label("License", systemImage: "doc.text")
                }
                .buttonStyle(.appSecondarySmall)
                Button { showingNotices = true } label: { Label("Acknowledgements", systemImage: "heart.text.square") }
                    .buttonStyle(.appSecondarySmall)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .sheet(isPresented: $showingNotices) { NoticesSheet() }
    }
}

/// The third-party notices bundled with the app (Sparkle, Argon2, EFF wordlist).
private struct NoticesSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let text: String = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Acknowledgements").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.appPrimarySmall).keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                Text(verbatim: text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(width: 620, height: 520)
    }
}

/// Click, then press the new key combination (needs ⌘, ⌥ or ⌃). Esc cancels.
private struct ShortcutRecorder: View {
    @State private var shortcut = Shortcut.palette
    @State private var recording = false
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        HStack(spacing: 8) {
            if let problem { Text(verbatim: problem).font(.caption).foregroundStyle(.orange) }
            Button { recording ? stop() : start() } label: {
                Text(recording ? String(localized: "Type shortcut…") : shortcut.display)
                    .font(.system(size: 12, weight: .semibold, design: recording ? .default : .rounded))
                    .frame(minWidth: 96)
            }
            .buttonStyle(.appSecondarySmall)
            .foregroundStyle(recording ? Color.secondary : .primary)
            if shortcut != .paletteDefault {
                Button { apply(.paletteDefault) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .help(Text("Reset to ⌘K"))
                    .accessibilityLabel(Text("Reset to ⌘K"))
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        problem = nil
        recording = true
        GlobalHotKey.palette?.pause() // or pressing the current shortcut would open the palette
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc
            if let new = Shortcut(event: event) { apply(new); stop() } else { problem = String(localized: "Include ⌘, ⌥ or ⌃") }
            return nil
        }
    }

    private func stop() {
        if recording, monitor != nil { GlobalHotKey.palette?.register(shortcut) }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func apply(_ new: Shortcut) {
        if GlobalHotKey.palette?.register(new) == false {
            problem = String(localized: "Another app uses \(new.display)")
            GlobalHotKey.palette?.register(shortcut)
            return
        }
        problem = nil
        shortcut = new
        Shortcut.palette = new
    }
}

/// The app's own language, chosen here: written to the app's `AppleLanguages` (read at launch), then a relaunch.
private struct LanguagePicker: View {
    /// "" follows the system.
    static let choices: [(code: String, name: String)] = [
        ("", String(localized: "System Default")), ("en", "English"), ("zh-Hant", "繁體中文"),
        ("zh-HK", "繁體中文（香港）"), ("zh-Hans", "简体中文"), ("ja", "日本語"),
    ]

    /// What the app was launched with ("" = the system's choice).
    private static let atLaunch: String = (UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"]
        as? [String])?.first ?? ""

    @State private var chosen = Self.atLaunch

    var body: some View {
        LabeledContent("Language") {
            HStack(spacing: 8) {
                if chosen != Self.atLaunch {
                    Button("Relaunch to Apply") { Self.relaunch() }
                        .buttonStyle(.appPrimarySmall)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                Picker("Language", selection: $chosen) {
                    ForEach(Self.choices, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .animation(.snappy(duration: 0.2), value: chosen)
        }
        .onChange(of: chosen) { _, code in
            if code.isEmpty {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            }
        }
    }

    /// Opens a fresh copy once this one has quit, so the new language loads.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
