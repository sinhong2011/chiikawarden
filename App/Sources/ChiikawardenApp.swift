import SwiftUI

@main
struct ChiikawardenApp: App {
    @State private var model = AppModel()
    @AppStorage(Pref.appearance) private var appearance = AppearanceSetting.system
    @State private var quickSearch: QuickSearchController?
    @State private var hotKey: GlobalHotKey?

    init() {
        Pref.register()
        #if DEBUG
        Snapshot.runIfRequested()
        SelfTest.runIfRequested()
        CloudSelfTest.runIfRequested()
        // `--demo`: open straight into the vault with demo items, for UI review.
        if CommandLine.arguments.contains("--demo") {
            let demo = AppModel()
            demo.items = Snapshot.demoItems
            demo.phase = .vault
            _model = State(initialValue: demo)
        }
        #endif
    }

    private let services = ServicesProvider()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.brand)
                .preferredColorScheme(appearance.scheme)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.appDidBecomeActive()
                }
                .onAppear {
                    NSApp.servicesProvider = services
                    NSUpdateDynamicServices()
                    model.startAutoLock()
                    if hotKey == nil {
                        let controller = QuickSearchController(model: model)
                        quickSearch = controller
                        model.openPalette = { controller.show() }
                        hotKey = GlobalHotKey { controller.toggle() }
                    }
                }
                // Soft pastel wash from the Liquid design under every screen.
                .containerBackground(for: .window) { WindowBackdrop() }
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .tint(.brand)
        } label: {
            Image(systemName: model.isUnlocked ? "lock.open" : "lock")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .tint(.brand)
                .preferredColorScheme(appearance.scheme)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Login") { model.editing = EditRequest(mode: .create(.login)) }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!model.isUnlocked)
                Button("New Secure Note") { model.editing = EditRequest(mode: .create(.secureNote)) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!model.isUnlocked)
                Menu("New Other Item") {
                    Button("Card") { model.editing = EditRequest(mode: .create(.card)) }
                    Button("Identity") { model.editing = EditRequest(mode: .create(.identity)) }
                    Button("SSH Key") { model.editing = EditRequest(mode: .create(.sshKey)) }
                }
                .disabled(!model.isUnlocked)
                Button("New Folder…") { model.promptingNewFolder = true }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                    .disabled(!model.isUnlocked)
                Divider()
                Button("Add Account…") { model.beginAddAccount() }
                    .disabled(!model.isUnlocked)
            }
            CommandMenu("Item") {
                let item = model.selectedItem
                Button("Edit") { if let item { model.editing = EditRequest(mode: .edit(item)) } }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(item == nil || item?.isDeleted == true)
                Divider()
                Button("Copy Username") { if let u = item?.username { model.copy(u, label: String(localized: "Username")) } }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(item?.kind != .login || item?.username == nil)
                Button("Copy Password") { if let p = item?.password { model.copy(p, label: String(localized: "Password")) } }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(item?.password == nil)
                Button("Copy One-Time Code") { if let t = item?.totp { model.copy(t.code(), label: String(localized: "Code")) } }
                    .keyboardShortcut("c", modifiers: [.command, .control])
                    .disabled(item?.totp == nil)
                Divider()
                Button("Toggle Favorite") { if let item { Task { await model.toggleFavorite(item) } } }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(item == nil || item?.isDeleted == true)
                Button("Move to Trash") { if let item { Task { await model.trash(item) } } }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(item == nil || item?.isDeleted == true)
            }
            CommandGroup(after: .appSettings) {
                Button("Command Palette") { quickSearch?.show() }
                    .keyboardShortcut(.space, modifiers: .option)
                Button("Lock Vault") { model.lock() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(!model.isUnlocked)
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.phase {
            case .login, .twoFactor, .deviceVerification, .ssoPassword:
                LoginView()
                    .frame(minWidth: 520, idealWidth: 920, maxWidth: 1600, minHeight: 600, idealHeight: 640, maxHeight: 1200)
                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 1.04).combined(with: .opacity)))
            case .locked:
                UnlockView()
                    .frame(minWidth: 520, idealWidth: 920, maxWidth: 1600, minHeight: 560, idealHeight: 600, maxHeight: 1200)
                    .transition(.opacity)
            case .vault:
                VaultView()
                    .frame(minWidth: 960, idealWidth: 1120, minHeight: 620, idealHeight: 720)
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: model.phase.id)
    }
}

extension Color {
    /// Brand blue, shared with the app icon (Assets: AccentColor, adapts to dark mode).
    static let brand = Color("AccentColor")
}

/// Wrapper so @AppStorage can drive preferredColorScheme.
enum AppearanceSetting: String {
    case system, light, dark
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}
