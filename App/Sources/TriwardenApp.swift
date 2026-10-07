import SwiftUI
import VaultwardenAPI

@main
struct TriwardenApp: App {
    @State private var model = AppModel()
    @AppStorage(Pref.appearance) private var appearance = AppearanceSetting.system

    init() {
        Pref.register()
        // One window with its own toolbar: no system tab bar (and no View › Show Tab Bar to turn it on).
        NSWindow.allowsAutomaticWindowTabbing = false
        #if DEBUG
        Snapshot.runIfRequested()
        SelfTest.runIfRequested()
        CloudSelfTest.runIfRequested()
        // `--demo`: open straight into the vault with demo items, for UI review.
        if CommandLine.arguments.contains("--demo") {
            let demo = AppModel()
            demo.items = Snapshot.demoItems
            // An in-memory account only: demo/UI-test runs never show or touch the real saved accounts.
            demo.setPreviewAccounts([SavedAccount(id: "demo", email: "usagi@triwarden.test", serverKind: "selfHosted",
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
            // No window-wide tint: a tint colours menu icons, and a highlighted row would then hide its own icon.
            // System controls take the neutral global accent (ControlAccent); the app's switches set their own.
            RootView()
                .environment(model)
                .preferredColorScheme(appearance.scheme)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.appDidBecomeActive()
                }
                .onAppear {
                    NSApp.servicesProvider = services
                    NSUpdateDynamicServices()
                    model.startAutoLock()
                    CaptureShield.start()
                }
                // Soft pastel wash from the Liquid design under every screen.
                .containerBackground(for: .window) { WindowBackdrop() }
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarGlyph.image)
                .opacity(model.isUnlocked ? 1 : 0.55)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
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
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(model.sessions.isEmpty)
                Button("Export Vault…") { model.beginExport() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.sessions.isEmpty)
            }
            CommandMenu("Item") {
                let item = model.selectedItem
                Button("Edit") { if let item { model.guarded(item) { model.editing = EditRequest(mode: .edit(item)) } } }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(item == nil || item?.isDeleted == true)
                Divider()
                Button("Copy Username") { if let u = item?.username { model.copy(u, label: String(localized: "Username")) } }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(item?.kind != .login || item?.username == nil)
                Button("Copy Password") { if let item { model.copyPassword(item) } }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(item?.password == nil)
                Button("Copy One-Time Code") { if let item, let t = item.totp { model.guarded(item) { model.copy(t.code(), label: String(localized: "Code")) } } }
                    .keyboardShortcut("c", modifiers: [.command, .control])
                    .disabled(item?.totp == nil)
                Button("Show Password in Large Type") { if let item { model.showLargeType(item) } }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                    .disabled(item?.password == nil)
                Divider()
                Button("Toggle Favorite") { if let item { Task { await model.toggleFavorite(item) } } }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(item == nil || item?.isDeleted == true)
                Button(item?.isArchived == true ? "Unarchive" : "Archive") {
                    if let item { Task { await model.setArchived(item, !item.isArchived) } }
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(item == nil || item?.isDeleted == true)
                Button("Move to Trash…") { if let item { model.confirmTrash(item) } }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(item == nil || item?.isDeleted == true)
            }
            CommandGroup(after: .appSettings) {
                Button("Command Palette") { model.openPalette() } // its shortcut is the global one from Settings
                Button("Lock Vault") { model.lock(animated: true) }
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

    /// Into the vault: the gate's heavy ease. Locking: the gate closing. Elsewhere: smooth, nothing wobbles into place.
    private var phaseAnimation: Animation {
        if model.phase.id == AppModel.Phase.vault.id { return .easeInOut(duration: 0.55) }
        return .smooth(duration: 0.45)
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
            case .locked, .vault:
                // Signed in: the vault is always the window; while locked, the lock lies over it as one layer.
                VaultView(initialSelection: DemoLaunch.item, initialSection: DemoLaunch.section)
                    .frame(minWidth: 380, idealWidth: 1120, minHeight: 520, idealHeight: 720)
                    // No blur or scaling of its own behind the lock (the lock's frosted layer blurs it): a blur would lay
                    // it out under the title bar, and it would jump into place on unlock.
                    // From login it's simply already there under the gate: no fade (a gap would show) and no blur or scale.
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    .zIndex(0)
            }
        }
        // The lock lies over the window as an overlay (not a sibling): it reaches under the title bar without
        // stretching the vault's layout there, so nothing moves when it lifts.
        .overlay {
            if model.phase.id == AppModel.Phase.locked.id {
                UnlockView()
                    // Appears and leaves at once: when animated, the gate's plates cover it while it does.
                    .transition(reduceMotion ? .opacity : .identity)
            }
        }
        // The gate: plates over everything, only while they move (locking and unlocking).
        .overlay {
            if model.gate != nil { GatePlates() }
        }
        .animation(phaseAnimation, value: model.phase.id)
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
    /// What system controls are tinted with — menu highlights and icons, pickers, switches, sliders, the Settings
    /// sidebar: a neutral graphite (Assets: ControlAccent), so no icon or label turns blue. The brand blue is only ever
    /// a fill the app draws on purpose: primary buttons, the vault's selection, header tiles.
    static let controlTint = Color("ControlAccent")
}

extension EnvironmentValues {
    /// True inside the gate's moving halves: animated content holds still there.
    @Entry var gatePassing = false
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
            // While the gate moves the door holds still in each half (it's at rest then anyway): its drawing doesn't
            // change, so SwiftUI keeps the rendered layers and only moves them. (No drawingGroup: it can't draw the
            // password field and other AppKit-backed views.)
            .environment(\.gatePassing, true)
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


/// Wrapper so @AppStorage can drive preferredColorScheme.
enum AppearanceSetting: String {
    case system, light, dark
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

/// `--demo` extras for screenshots: `--demo-section codes|generator|watchtower|sends` opens that page,
/// `--demo-item <id>` selects a demo item. Nil in release builds and normal runs.
enum DemoLaunch {
    static var section: SidebarSelection? {
        #if DEBUG
        switch value(after: "--demo-section") {
        case "codes": return .codes
        case "generator": return .generator
        case "watchtower": return .watchtower
        case "sends": return .sends
        default: return nil
        }
        #else
        return nil
        #endif
    }

    static var item: VaultItem.ID? {
        #if DEBUG
        return value(after: "--demo-item")
        #else
        return nil
        #endif
    }

    private static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let at = args.firstIndex(of: flag), at + 1 < args.count else { return nil }
        return args[at + 1]
    }
}
