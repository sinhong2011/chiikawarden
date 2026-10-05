import SwiftUI

@main
struct ChiikawardenApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.brand)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
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
            case .login, .twoFactor:
                LoginView()
                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 1.04).combined(with: .opacity)))
            case .vault:
                VaultView()
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
