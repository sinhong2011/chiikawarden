#if DEBUG
import SwiftUI
import VaultwardenAPI

/// Sample models for the Xcode canvas, built from the same demo vault as `--snapshot`.
/// Open any file with a `#Preview` below and press ⌥⌘↩ to show the canvas.
@MainActor
enum PreviewModels {
    static var login: AppModel {
        let model = AppModel()
        model.phase = .login
        model.serverKind = .selfHosted
        model.serverURL = "https://vault.home.arpa"
        model.email = "usagi@triwarden.test"
        model.serverStatus = .reachable(product: "Vaultwarden", version: "2026.6.0")
        return model
    }

    static var locked: AppModel {
        let model = login
        model.setPreviewAccounts([
            SavedAccount(id: "a", email: "usagi@triwarden.test", serverKind: "selfHosted", serverURL: "https://vault.home.arpa",
                         kdf: .pbkdf2(iterations: 600_000), protectedUserKey: ""),
        ])
        model.phase = .locked
        return model
    }

    static var vault: AppModel {
        let model = AppModel()
        model.phase = .vault
        model.items = Snapshot.demoItems
        model.previewUnlocked = true
        model.selectedID = Snapshot.demoItems.first { $0.kind == .login }?.id
        model.rememberGenerated("correct-Horse-battery-staple4", kind: "passphrase")
        model.rememberGenerated("k#9vR!2mWq$7zLp", kind: "password")
        return model
    }
}

private extension View {
    /// The app's window backdrop and brand tint, as in the real window.
    func previewChrome() -> some View { Snapshot.desktop(tint(.brand), dark: false) }
}

#Preview("Login", traits: .fixedLayout(width: 920, height: 640)) {
    LoginView().environment(PreviewModels.login).previewChrome()
}

#Preview("Unlock", traits: .fixedLayout(width: 920, height: 600)) {
    UnlockView().environment(PreviewModels.locked).previewChrome()
}

#Preview("Unlock · phone width", traits: .fixedLayout(width: 390, height: 700)) {
    UnlockView().environment(PreviewModels.locked).previewChrome()
}

#Preview("Vault", traits: .fixedLayout(width: 1180, height: 760)) {
    VaultView().environment(PreviewModels.vault)
}

#Preview("Vault · narrow", traits: .fixedLayout(width: 760, height: 760)) {
    VaultView().environment(PreviewModels.vault)
}

#Preview("Vault · phone width", traits: .fixedLayout(width: 390, height: 760)) {
    VaultView().environment(PreviewModels.vault)
}

#Preview("Generator", traits: .fixedLayout(width: 1000, height: 720)) {
    ScrollView { GeneratorView().padding(28) }.environment(PreviewModels.vault).previewChrome()
}

#Preview("Generator popover", traits: .sizeThatFitsLayout) {
    GeneratorView(compact: true).environment(PreviewModels.vault).tint(.brand)
}

#Preview("Command palette", traits: .fixedLayout(width: 700, height: 620)) {
    CommandPalette(close: {}).environment(PreviewModels.vault).previewChrome()
}

#Preview("One-Time Codes", traits: .fixedLayout(width: 900, height: 560)) {
    CodesPane().environment(PreviewModels.vault).previewChrome()
}

#Preview("Edit item", traits: .fixedLayout(width: 540, height: 620)) {
    EditItemSheet(mode: .edit(Snapshot.demoItems[1])).environment(PreviewModels.vault).tint(.brand)
}

#Preview("Menu bar", traits: .sizeThatFitsLayout) {
    MenuBarContent().environment(PreviewModels.vault).tint(.brand)
}
#endif
