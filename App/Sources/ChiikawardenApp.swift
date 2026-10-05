import SwiftUI
import VaultwardenAPI

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
            // An in-memory account only: demo/UI-test runs never show or touch the real saved accounts.
            demo.setPreviewAccounts([SavedAccount(id: "demo", email: "usagi@chiikawarden.test", serverKind: "selfHosted",
                                                  serverURL: "https://vault.home.arpa", kdf: .pbkdf2(iterations: 600_000),
                                                  protectedUserKey: "")])
            demo.previewUnlocked = true
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
                        let key = GlobalHotKey(Shortcut.palette) { controller.toggle() }
                        hotKey = key
                        GlobalHotKey.palette = key
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
            Image(nsImage: MenuBarGlyph.image)
                .opacity(model.isUnlocked ? 1 : 0.55)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .tint(.brand)
                .preferredColorScheme(appearance.scheme)
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)
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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { model.updates.checkForUpdates() }
                    .disabled(!model.updates.canCheck)
            }
            CommandGroup(replacing: .importExport) {
                Button("Import…") { model.beginImport() }
                    .disabled(model.sessions.isEmpty)
                Button("Export Vault…") { model.beginExport() }
                    .disabled(model.sessions.isEmpty)
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
                Button("Move to Trash…") { if let item { model.confirmTrash(item) } }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(item == nil || item?.isDeleted == true)
            }
            CommandGroup(after: .appSettings) {
                Button("Command Palette") { quickSearch?.show() } // its shortcut is the global one from Settings
                Button("Lock Vault") { model.lock() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(!model.isUnlocked)
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The login and lock screens leave like a vault's inner gate: split along the middle, halves retracting up and down.
    private var gate: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity,
                                              removal: .modifier(active: GateSplit(progress: 1), identity: GateSplit(progress: 0)))
    }

    var body: some View {
        @Bindable var model = model
        ZStack {
            switch model.phase {
            case .login, .twoFactor, .deviceVerification, .ssoPassword:
                LoginView()
                    .frame(minWidth: 380, idealWidth: 920, maxWidth: .infinity, minHeight: 560, idealHeight: 640, maxHeight: .infinity)
                    .transition(gate)
                    .zIndex(1) // the gate opens over the vault
            case .locked:
                UnlockView()
                    .frame(minWidth: 380, idealWidth: 920, maxWidth: .infinity, minHeight: 520, idealHeight: 600, maxHeight: .infinity)
                    .transition(gate)
                    .zIndex(1)
            case .vault:
                VaultView()
                    .frame(minWidth: 380, idealWidth: 1120, minHeight: 520, idealHeight: 720)
                    // Already waiting behind the gate; it settles forward as the halves part.
                    .transition(.asymmetric(insertion: reduceMotion ? .opacity
                                                : .modifier(active: SceneFade(scale: 0.97, blur: 3, opacity: 1),
                                                            identity: SceneFade(scale: 1, blur: 0, opacity: 1)),
                                            removal: .opacity))
                    .zIndex(0)
            }
        }
        // Into the vault: the gate's heavy ease. Elsewhere: a light spring.
        .animation(model.phase.id == AppModel.Phase.vault.id ? .easeInOut(duration: 0.75) : .spring(duration: 0.5, bounce: 0.2),
                   value: model.phase.id)
        .onAppear { model.openSettingsAction = { openSettings() } }
        // Every destructive action asks here first.
        .confirmationDialog(model.confirming?.title ?? "", isPresented: Binding(
            get: { model.confirming != nil }, set: { if !$0 { model.confirming = nil } }), presenting: model.confirming) { request in
            Button(request.action, role: .destructive) { Task { await request.run() } }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(request.message)
        }
    }
}

extension Color {
    /// Brand blue, shared with the app icon (Assets: AccentColor, adapts to dark mode).
    static let brand = Color("AccentColor")
}

/// The gate: while opening, the screen is drawn as two halves, the top one sliding up and the bottom one down, each
/// casting a shadow from its edge. Closed, it's just the screen. Animatable, so the halves move every frame.
struct GateSplit: ViewModifier, Animatable {
    var progress: CGFloat
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        if progress <= 0.001 {
            content
        } else {
            GeometryReader { geo in
                let travel = geo.size.height / 2 + 60
                ZStack {
                    half(content, top: true, height: geo.size.height)
                        .offset(y: -progress * travel)
                    half(content, top: false, height: geo.size.height)
                        .offset(y: progress * travel)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func half(_ content: Content, top: Bool, height: CGFloat) -> some View {
        content
            .mask(alignment: top ? .top : .bottom) { Rectangle().frame(height: height / 2) }
            .overlay(alignment: .top) {
                // The gate's edge: a dark seam with a thin highlight inside, so the halves read as heavy plates.
                VStack(spacing: 0) {
                    if !top { Rectangle().fill(.black.opacity(0.22)).frame(height: 2) }
                    Rectangle().fill(.white.opacity(0.4)).frame(height: 1)
                    if top { Rectangle().fill(.black.opacity(0.22)).frame(height: 2) }
                }
                .offset(y: top ? height / 2 - 3 : height / 2)
            }
            .shadow(color: .black.opacity(0.35 * Double(min(progress * 3, 1))), radius: 22, y: top ? 14 : -14)
    }
}

/// Scale + blur + opacity, for the lock screen ⇄ vault hand-off.
private struct SceneFade: ViewModifier {
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.scaleEffect(scale).blur(radius: blur).opacity(opacity)
    }
}

/// Wrapper so @AppStorage can drive preferredColorScheme.
enum AppearanceSetting: String {
    case system, light, dark
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}
