#if DEBUG
import AppKit
import ChiikawaCrypto
import SwiftUI

/// Debug-only: `Chiikawarden --snapshot` renders key screens offscreen in light and dark
/// to PNGs, so UI can be reviewed without screen-recording permission. Exits when done.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.contains("--snapshot") else { return }
        // Sandboxed: write inside our container and print the path.
        let dir = FileManager.default.temporaryDirectory.appending(path: "snapshots", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = AppModel()
        model.serverKind = .selfHosted
        model.serverURL = "https://vault.home.arpa"
        model.email = "usagi@chiikawarden.test"
        model.serverStatus = .reachable(product: "Vaultwarden", version: "2026.6.0")
        model.touchIDEnabled = true

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(desktop(LoginView().environment(model).tint(.brand), dark: name == "dark"),
                   size: CGSize(width: 900, height: 600), appearance: appearance,
                   to: dir.appending(path: "login-\(name).png"))
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(desktop(UnlockView().environment(model).tint(.brand), dark: name == "dark"),
                   size: CGSize(width: 900, height: 600), appearance: appearance,
                   to: dir.appending(path: "unlock-\(name).png"))
        }

        let vault = AppModel()
        vault.phase = .vault
        vault.items = demoItems
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(desktop(VaultView().environment(vault).tint(.brand), dark: name == "dark"),
                   size: CGSize(width: 1180, height: 760), appearance: appearance,
                   to: dir.appending(path: "vault-\(name).png"))
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(QuickSearchView(close: {}).environment(vault).tint(.brand).padding(30),
                   size: CGSize(width: 700, height: 480), appearance: appearance,
                   to: dir.appending(path: "quicksearch-\(name).png"))
            render(MenuBarContent().environment(vault).tint(.brand).background(Color.windowBase),
                   size: CGSize(width: 300, height: 460), appearance: appearance,
                   to: dir.appending(path: "menubar-\(name).png"))
        }
        render(desktop(VaultView(initialSelection: "7").environment(vault).tint(.brand), dark: false),
               size: CGSize(width: 1180, height: 760), appearance: .aqua, to: dir.appending(path: "vault-card-light.png"))
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(SettingsView().environment(model).tint(.brand),
                   size: CGSize(width: 600, height: 520), appearance: appearance,
                   to: dir.appending(path: "settings-\(name).png"))
        }
        print(dir.path)
        exit(0)
    }

    /// Paints the window base, which `containerBackground` provides in the real window.
    private static func desktop(_ view: some View, dark: Bool) -> some View {
        ZStack {
            Color.windowBase
            view
        }
    }

    static let demoItems: [VaultItem] = [
        VaultItem(id: "1", name: "Cloudflare", username: "ops@momonga.dev", host: "dash.cloudflare.com",
                  password: "cf-9xQ!m2Lp#Vt7", totp: TOTP("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"), notes: nil, favorite: false),
        VaultItem(id: "2", name: "GitHub", username: "usagi", host: "github.com", password: "m7Kq#vR2!tLp9wZe$Hu",
                  totp: TOTP("JBSWY3DPEHPK3PXP"), notes: "Recovery codes are in the “GitHub recovery” note.", favorite: true,
                  hasPasskey: true),
        VaultItem(id: "3", name: "Proton Mail", username: "usagi@proton.me", host: "account.proton.me",
                  password: "pm-4Rt$w8Nq!zK", totp: nil, notes: nil, favorite: false, hasPasskey: true),
        VaultItem(id: "4", name: "Synology NAS", username: "admin", host: "nas.home.arpa", password: "reused-password",
                  totp: nil, notes: nil, favorite: false, reuseCount: 1),
        VaultItem(id: "6", kind: .sshKey, name: "homelab-ed25519", username: nil, host: nil, password: nil,
                  totp: nil, notes: nil, favorite: false),
        VaultItem(id: "7", kind: .card, name: "Travel Visa", username: "•••• 6411", host: nil, password: nil,
                  totp: nil, notes: nil, favorite: false,
                  fields: [ItemField(label: "Card number", value: "4111111111116411", secret: true, monospaced: true),
                           ItemField(label: "Cardholder", value: "Usagi"), ItemField(label: "Expires", value: "08/2029"),
                           ItemField(label: "Security code", value: "123", secret: true, monospaced: true)]),
        VaultItem(id: "5", name: "Tailscale", username: "usagi", host: "login.tailscale.com", password: "ts-Lw8!r2Kq$7m",
                  totp: TOTP("JBSWY3DPEHPK3PXQ"), notes: nil, favorite: true),
    ]

    private static func render(_ view: some View, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        window.makeKey()
        host.layoutSubtreeIfNeeded()
        // Let one run-loop turn pass so async layout and images settle.
        RunLoop.main.run(until: .now + 1.0)
        // Capture the frame view so the window background is included (sidebar vibrancy still isn't).
        let frame = host.superview ?? host
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
#endif

#if DEBUG
/// Debug-only: `Chiikawarden --selftest <server> <email> <password>` runs the account lifecycle inside the
/// real (signed, sandboxed) app: log in → lock → offline unlock from cache → resume session → wrong password → log out.
@MainActor
enum SelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest"), i + 3 < args.count else { return }
        let (server, email, password) = (args[i + 1], args[i + 2], args[i + 3])
        Task {
            var failures = 0
            func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { failures += 1 } }

            let model = AppModel()
            model.logOut()
            model.serverKind = .selfHosted
            model.serverURL = server
            model.email = email
            await model.login(password: password)
            check(model.isUnlocked && !model.items.isEmpty, "login + sync (\(model.items.count) items)")
            check(AccountStore.load() != nil && AccountStore.loadCache() != nil && AccountStore.refreshToken != nil,
                  "account, encrypted cache and refresh token persisted")
            let count = model.items.count

            model.lock()
            check(model.phase.id == AppModel.Phase.locked.id && model.items.isEmpty, "lock clears vault, shows unlock")

            let fresh = AppModel() // simulates relaunch
            check(fresh.phase.id == AppModel.Phase.locked.id, "relaunch starts locked")
            await fresh.unlock(password: "definitely-wrong")
            check(!fresh.isUnlocked && fresh.errorMessage != nil, "wrong password rejected offline")
            await fresh.unlock(password: password)
            check(fresh.isUnlocked && fresh.items.count == count, "offline unlock restores \(fresh.items.count) items from cache")
            try? await Task.sleep(for: .seconds(3))
            check(fresh.lastSynced != nil, "session resumed with refresh token and re-synced")

            fresh.logOut()
            check(AccountStore.load() == nil && AccountStore.refreshToken == nil, "log out erases account and token")
            print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
    }
}
#endif
