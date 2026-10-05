import SwiftUI

@main
struct ChiikawardenApp: App {
    @State private var model = AppModel()
    @AppStorage(Pref.appearance) private var appearance = AppearanceSetting.system

    init() {
        Pref.register()
        #if DEBUG
        Snapshot.runIfRequested()
        SelfTest.runIfRequested()
        // `--demo`: open straight into the vault with demo items, for UI review.
        if CommandLine.arguments.contains("--demo") {
            let demo = AppModel()
            demo.items = Snapshot.demoItems
            demo.phase = .vault
            _model = State(initialValue: demo)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.brand)
                .preferredColorScheme(appearance.scheme)
                .onAppear { model.startAutoLock() }
                // Solid soft base from the spec (light lavender-gray / deep graphite); no glass.
                .containerBackground(Color.windowBase, for: .window)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(model)
                .tint(.brand)
                .preferredColorScheme(appearance.scheme)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appSettings) {
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
            case .login, .twoFactor, .deviceVerification:
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
