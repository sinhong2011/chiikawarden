import SSHAgent
import AppIntents
import AuthenticationServices
#if DEBUG
import AppKit
import ChiikawaCrypto
import SwiftUI
import VaultwardenAPI

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
        let custom = AppModel()
        custom.serverKind = .selfHosted
        custom.serverURL = "https://vault.example.com"
        custom.customIdentity = "https://login.example.com"
        custom.customNotifications = "http://push.example.com"
        render(desktop(LoginView().environment(custom).tint(.brand), dark: false),
               size: CGSize(width: 900, height: 760), appearance: .aqua, to: dir.appending(path: "login-custom-light.png"))
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(desktop(UnlockView().environment(model).tint(.brand), dark: name == "dark"),
                   size: CGSize(width: 900, height: 600), appearance: appearance,
                   to: dir.appending(path: "unlock-\(name).png"))
        }

        // The vault door's sequence, frozen at key moments.
        let doorFrames: [(String, VaultDoorStage.Motion)] = [
            ("0-closed", .init()),
            ("1-dial", .init(dial: -250, wheel: 40)),
            ("2-bolts", .init(dial: -216, wheel: 150, bolts: 1)),
            ("3-swing", .init(dial: -216, wheel: 150, bolts: 1, swing: 0.55, light: 0.4)),
            ("4-light", .init(dial: -216, wheel: 150, bolts: 1, swing: 0.95, light: 0.9)),
        ]
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (frame, motion) in doorFrames {
                // ImageRenderer draws SwiftUI's 3D projection (the swing); the window cache would drop it.
                let renderer = ImageRenderer(content: VaultDoorStage(frozen: motion).environment(model)
                    .environment(\.colorScheme, name == "dark" ? .dark : .light).frame(width: 520, height: 600))
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appending(path: "door-\(frame)-\(name).png"))
                }
            }
        }

        // The unlock animation's open moment, and Settings at its default size.
        let opening = AppModel()
        opening.setPreviewAccounts([SavedAccount(id: "a", email: "usagi@chiikawarden.test", serverKind: "selfHosted",
                                                 serverURL: "https://vault.home.arpa", kdf: .pbkdf2(iterations: 600_000), protectedUserKey: "")])
        opening.unlockOpening = true
        render(desktop(UnlockView().environment(opening).tint(.brand), dark: false),
               size: CGSize(width: 900, height: 600), appearance: .aqua, to: dir.appending(path: "unlock-opening-light.png"))
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(SettingsView().environment(model).tint(.brand), size: CGSize(width: 820, height: 640),
                   appearance: appearance, to: dir.appending(path: "settings-\(name).png"))
        }

        let multi = AppModel()
        multi.setPreviewAccounts([
            SavedAccount(id: "a", email: "usagi@chiikawarden.test", serverKind: "selfHosted", serverURL: "https://vault.home.arpa",
                         kdf: .pbkdf2(iterations: 600_000), protectedUserKey: ""),
            SavedAccount(id: "b", email: "usagi@work.example", serverKind: "bitwardenUS", serverURL: "",
                         kdf: .pbkdf2(iterations: 600_000), protectedUserKey: ""),
        ])
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(desktop(UnlockView().environment(multi).tint(.brand), dark: name == "dark"),
                   size: CGSize(width: 900, height: 640), appearance: appearance,
                   to: dir.appending(path: "unlock-multi-\(name).png"))
        }

        let vault = AppModel()
        vault.phase = .vault
        vault.items = demoItems.map { item in
            var item = item
            item.revised = Date(timeIntervalSince1970: 1_791_123_456) // a fixed moment, so renders don't change
            item.created = Date(timeIntervalSince1970: 1_748_500_000)
            return item
        }
        vault.previewUnlocked = true
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(desktop(VaultView().environment(vault).tint(.brand), dark: name == "dark"),
                   size: CGSize(width: 1180, height: 760), appearance: appearance,
                   to: dir.appending(path: "vault-\(name).png"))
            render(desktop(CodesPane().environment(vault).tint(.brand), dark: name == "dark"),
                   size: CGSize(width: 900, height: 560), appearance: appearance, to: dir.appending(path: "codes-\(name).png"))
            renderWindow(VaultView().environment(vault).tint(.brand), size: CGSize(width: 1180, height: 760),
                         appearance: appearance, to: dir.appending(path: "window-\(name).png"))
            renderWindow(VaultView().environment(vault).tint(.brand), size: CGSize(width: 430, height: 760),
                         resizeFrom: CGSize(width: 1180, height: 760),
                         appearance: appearance, to: dir.appending(path: "window-resized-\(name).png"))
            for (w, d) in [(400, 0), (760, 0), (400, 2)] {
                renderWindow(VaultView(initialDepth: d).environment(vault).tint(.brand), size: CGSize(width: CGFloat(w), height: 760),
                             appearance: appearance, to: dir.appending(path: "window-\(w)-depth\(d)-\(name).png"))
            }
            for w in [760, 400] {
                renderWindow(VaultView().environment(vault).tint(.brand), size: CGSize(width: CGFloat(w), height: 760),
                             appearance: appearance, to: dir.appending(path: "window-\(w)-\(name).png"))
            }
            renderWindow(UnlockView().environment(vault).tint(.brand), size: CGSize(width: 400, height: 640),
                         appearance: appearance, to: dir.appending(path: "unlock-400-\(name).png"))
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(desktop(CommandPalette(close: {}).environment(vault).tint(.brand), dark: name == "dark"),
                   size: CGSize(width: 760, height: 620), appearance: appearance,
                   to: dir.appending(path: "palette-\(name).png"))
            render(MenuBarContent().environment(vault).tint(.brand).background(.regularMaterial),
                   size: CGSize(width: 372, height: 640), appearance: appearance,
                   to: dir.appending(path: "menubar-\(name).png"))
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(EditItemSheet(mode: .edit(demoItems[1])).environment(vault).tint(.brand),
                   size: CGSize(width: 520, height: 560), appearance: appearance,
                   to: dir.appending(path: "edit-\(name).png"))
            var card = demoItems.first { $0.kind == .card }!
            card.properties = ["cardholderName": "Usagi", "brand": "Visa", "number": "4111111111116411", "expMonth": "8", "expYear": "2029", "code": "123"]
            card.customFields = [CustomField(name: "PIN", value: "0420", kind: .hidden), CustomField(name: "Virtual", value: "true", kind: .boolean)]
            render(EditItemSheet(mode: .edit(card)).environment(vault).tint(.brand),
                   size: CGSize(width: 540, height: 620), appearance: appearance,
                   to: dir.appending(path: "edit-card-\(name).png"))
            render(EditItemSheet(mode: .create(.identity)).environment(vault).tint(.brand),
                   size: CGSize(width: 540, height: 620), appearance: appearance,
                   to: dir.appending(path: "edit-identity-\(name).png"))
            render(EditItemSheet(mode: .create(.sshKey)).environment(vault).tint(.brand),
                   size: CGSize(width: 540, height: 620), appearance: appearance,
                   to: dir.appending(path: "edit-ssh-\(name).png"))
            if vault.generatorHistory.isEmpty {
                vault.rememberGenerated("correct-Horse-battery-staple4", kind: "passphrase")
                vault.rememberGenerated("k#9vR!2mWq$7zLp", kind: "password")
                vault.rememberGenerated("usagi+k3x9q2ma@proton.me", kind: "username")
            }
            render(desktop(ExportSheet().environment(vault).tint(.brand), dark: name == "dark"),
                   size: CGSize(width: 500, height: 600), appearance: appearance, to: dir.appending(path: "export-\(name).png"))
            render(desktop(ImportSheet().environment(vault).tint(.brand), dark: name == "dark"),
                   size: CGSize(width: 520, height: 420), appearance: appearance, to: dir.appending(path: "import-\(name).png"))
            for (label, size) in [("", CGSize(width: 1120, height: 760)), ("-narrow", CGSize(width: 680, height: 900))] {
                render(desktop(GeometryReader { geo in
                    ScrollView { GeneratorView().padding(28).frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top) }
                }.environment(vault).tint(.brand), dark: name == "dark"),
                       size: size, appearance: appearance,
                       to: dir.appending(path: "generator\(label)-\(name).png"))
            }
        }
        vault.sends = [
            SendItem(id: "s1", accountId: "", accessId: "a1", kind: .text, name: "Wi-Fi for guests", notes: nil,
                     text: "pochi-net / yaha-1234", hideText: true, fileName: nil, sizeName: nil, keyMaterial: Data(count: 16),
                     accessCount: 1, maxAccessCount: 3, hasPassword: true, disabled: false,
                     deletionDate: .now.addingTimeInterval(5 * 86_400), expirationDate: nil),
            SendItem(id: "s2", accountId: "", accessId: "a2", kind: .file, name: "Lease scan", notes: "for the agent",
                     text: nil, hideText: false, fileName: "lease-2026.pdf", sizeName: "1.2 MB", keyMaterial: Data(count: 16),
                     accessCount: 0, maxAccessCount: nil, hasPassword: false, disabled: false,
                     deletionDate: .now.addingTimeInterval(86_400), expirationDate: nil),
        ]
        vault.selectedSendID = "s1"
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(desktop(SendsPane().environment(vault).tint(.brand).padding(14), dark: name == "dark"),
                   size: CGSize(width: 960, height: 640), appearance: appearance,
                   to: dir.appending(path: "send-\(name).png"))
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let locked = AutoFillState()
            locked.domains = ["github.com"]
            locked.email = "usagi@chiikawarden.test"
            locked.touchIDEnabled = true
            locked.hasAccount = true
            render(AutoFillView(state: locked).background(Color.windowBase), size: CGSize(width: 440, height: 500),
                   appearance: appearance, to: dir.appending(path: "autofill-locked-\(name).png"))
            let open = AutoFillState()
            open.domains = ["github.com"]
            open.items = demoItems.filter { $0.kind == .login }
            open.unlocked = true
            open.hasAccount = true
            render(AutoFillView(state: open).background(Color.windowBase), size: CGSize(width: 440, height: 500),
                   appearance: appearance, to: dir.appending(path: "autofill-list-\(name).png"))
            let register = AutoFillState()
            register.begin(passkey: .init(rpId: "github.com", clientDataHash: Data(), userName: "usagi"), registering: true)
            register.items = demoItems.filter { $0.kind == .login }
            register.unlocked = true
            register.hasAccount = true
            render(AutoFillView(state: register).background(Color.windowBase), size: CGSize(width: 440, height: 500),
                   appearance: appearance, to: dir.appending(path: "autofill-passkey-\(name).png"))
        }
        vault.breachCounts = ["4": 1203]
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(desktop(WatchtowerView(onOpen: { _ in }).environment(vault).tint(.brand), dark: name == "dark"),
                   size: CGSize(width: 820, height: 760), appearance: appearance,
                   to: dir.appending(path: "watchtower-\(name).png"))
        }
        vault.breachCounts = nil
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
    static func desktop(_ view: some View, dark: Bool) -> some View {
        ZStack {
            WindowBackdrop()
            view
        }
    }

    /// Runs a command-line tool for the self-test.
    /// Runs off the main actor: the SSH agent being tested needs the main actor to answer.
    nonisolated static func tool(_ name: String, _ args: [String], env: [String: String] = [:], stdin: Data? = nil) async -> (status: Int32, output: String) {
        await Task.detached { runTool(name, args, env: env, stdin: stdin) }.value
    }

    nonisolated static func runTool(_ name: String, _ args: [String], env: [String: String], stdin: Data?) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(filePath: name.hasPrefix("/") ? name : "/usr/bin/\(name)")
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        let out = Pipe(), input = Pipe()
        p.standardOutput = out; p.standardError = out; p.standardInput = input
        do { try p.run() } catch { return (-1, "\(error)") }
        if let stdin { input.fileHandleForWriting.write(stdin) }
        try? input.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static let demoItems: [VaultItem] = [
        VaultItem(id: "1", name: "Cloudflare", username: "ops@momonga.dev", host: "dash.cloudflare.com",
                  password: "cf-9xQ!m2Lp#Vt7", totp: TOTP("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"), notes: nil, favorite: false),
        VaultItem(id: "2", name: "GitHub", username: "usagi", host: "github.com", password: "m7Kq#vR2!tLp9wZe$Hu",
                  totp: TOTP("JBSWY3DPEHPK3PXP"), notes: "Recovery codes are in the “GitHub recovery” note.", favorite: true,
                  hasPasskey: true,
                  passkeys: [PasskeyCredential(credentialId: "demo", keyValue: "", rpId: "github.com", userName: "usagi",
                                               creationDate: Date(timeIntervalSince1970: 1_780_000_000))],
                  attachments: [VaultItem.Attachment(id: "a1", fileName: "github-recovery-codes.txt", size: 912, sizeName: "912 bytes",
                                                     fileKey: try! SymmetricKeyPair(combined: Data(count: 64))),
                                VaultItem.Attachment(id: "a2", fileName: "2fa-backup.pdf", size: 48_000, sizeName: "48 KB",
                                                     fileKey: try! SymmetricKeyPair(combined: Data(count: 64)))]),
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

    /// A real window with SwiftUI's toolbar bridged in, so toolbar items render as in the app.
    /// `resizeFrom`: open at that size first, then shrink to `size` — like dragging the window edge.
    private static func renderWindow(_ view: some View, size: CGSize, resizeFrom: CGSize? = nil, appearance: NSAppearance.Name, to url: URL) {
        let controller = NSHostingController(rootView: view.frame(minWidth: 380, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity))
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(resizeFrom ?? size)
        window.orderFrontRegardless()
        window.makeKey()
        RunLoop.main.run(until: .now + 1.5)
        if resizeFrom != nil {
            window.setContentSize(size)
            RunLoop.main.run(until: .now + 1.5)
        }
        guard let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

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
    /// `--selftest <server> <email> <password> [<second email> <second password>]`
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest"), i + 3 < args.count else { return }
        let (server, email, password) = (args[i + 1], args[i + 2], args[i + 3])
        let second = i + 5 < args.count ? (args[i + 4], args[i + 5]) : nil
        // Isolated storage: the self-test must never see or erase the user's real accounts.
        AccountStore.namespace = "SelfTestAccounts"
        AutoFillIdentities.isEnabled = false
        Task {
            var failures = 0
            func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { failures += 1 } }

            let model = AppModel()
            for account in model.accounts { model.logOut(account.id) }
            model.serverKind = .selfHosted
            model.serverURL = server
            model.email = email
            await model.login(password: password)
            let firstID = SavedAccount.makeID(serverKind: "selfHosted", serverURL: server, email: email)
            check(model.isUnlocked && !model.items.isEmpty, "login + sync (\(model.items.count) items) \(model.errorMessage ?? "")")
            check(AccountStore.load(firstID) != nil && AccountStore.loadCache(firstID) != nil && AccountStore.refreshToken(firstID) != nil,
                  "account, encrypted cache and refresh token persisted")
            check(Keychain.isShared(service: "io.github.sinhong2011.chiikawarden.SelfTestAccounts.refresh.\(firstID)"),
                  "refresh token in the App Group keychain (AutoFill can save passkeys)")
            let count = model.items.count
            let org = model.organizations.first
            let collection = org?.children.first
            check(org != nil && collection != nil, "organization “\(org?.name ?? "-")” with collection “\(collection?.name ?? "-")”")
            if let org, let collection {
                check(model.items.contains { SidebarSelection.organization(org.id).includes($0) }
                      && model.items.contains { SidebarSelection.collection(collection.id).includes($0) },
                      "org and collection filters match their items")
            }

            // Watchtower on the seeded vault.
            let report = WatchtowerReport(items: model.items, breaches: nil)
            let names = { (issue: WatchtowerReport.Issue) in Set(report.issues[issue, default: []].map(\.name)) }
            check(names(.weak).contains("Weak example") && names(.reused).isSuperset(of: ["Synology NAS", "Router"])
                  && !names(.insecure).contains("Router"),
                  "watchtower: weak, reused, private-IP http not flagged")
            await model.checkBreaches()
            let breached = Set(WatchtowerReport(items: model.items, breaches: model.breachCounts).issues[.breached, default: []].map(\.name))
            check(breached.contains("Weak example") && !breached.contains("GitHub"), "breach check (k-anonymity) flags 123456 only among known")

            // Folders: nested names, moving items, parent selection includes children, highlighting.
            let parentID = await model.createFolder(name: "Selftest")
            let childID = await model.createFolder(name: "Selftest/Nested")
            _ = await model.createItem(.login, edit: CipherEdit(name: "Folder Test Item", username: "f", password: "x"))
            if let item = model.items.first(where: { $0.name == "Folder Test Item" }), let childID {
                await model.move(itemIDs: [item.id], toFolderIn: [childID])
                let movedItem = model.items.first { $0.id == item.id }
                let tree = FolderNode.tree(model.folders)
                let parentNode = tree.first { $0.path == "Selftest" }
                check(movedItem?.folderId == childID && parentNode?.children.first?.path == "Selftest/Nested",
                      "move item into nested folder; tree nests Selftest › Nested")
                check(movedItem.map { SidebarSelection.folder("Selftest").includes($0) && SidebarSelection.folder("Selftest/Nested").includes($0) } == true,
                      "selecting the parent folder includes items in subfolders")
                let marked = Highlight.marked("Folder Test Item", "test")
                check(marked.runs.contains { $0.backgroundColor != nil }, "search match highlighting")
                if let movedItem { await model.deleteForever(movedItem) }
            } else {
                check(false, "folder setup")
            }
            if let childID { await model.deleteFolder(childID) }
            if let parentID { await model.deleteFolder(parentID) }

            // Editing lifecycle through the app model.
            let created = await model.createItem(.login, edit: CipherEdit(name: "Selftest Item", username: "u", password: "p-old", uri: "https://example.org"))
            let new = model.items.first { $0.name == "Selftest Item" }
            check(created && new != nil && model.selectedID == new?.id, "create login (selected after save)")
            if let new {
                await model.updateItem(new.id, edit: CipherEdit(name: "Selftest Edited", password: "p-new"))
                let edited = model.items.first { $0.id == new.id }
                check(edited?.name == "Selftest Edited" && edited?.password == "p-new" && edited?.username == "u", "edit keeps untouched fields")
                if let edited { await model.toggleFavorite(edited) }
                check(model.items.first { $0.id == new.id }?.favorite == true, "toggle favorite")
                if let starred = model.items.first(where: { $0.id == new.id }) { await model.toggleFavorite(starred) }
                check(model.items.first { $0.id == new.id }?.favorite == false, "toggle favorite off again")
                if let item = model.items.first(where: { $0.id == new.id }) { await model.trash(item) }
                check(model.items.first { $0.id == new.id }?.isDeleted == true, "move to Trash")
                if let item = model.items.first(where: { $0.id == new.id }) { await model.restore(item) }
                check(model.items.first { $0.id == new.id }?.isDeleted == false, "restore from Trash")
                if let item = model.items.first(where: { $0.id == new.id }) { await model.deleteForever(item) }
                check(!model.items.contains { $0.id == new.id }, "delete forever")
            }

            // Cards, identities, SSH keys and custom fields.
            do {
                var cardEdit = CipherEdit(name: "Selftest card")
                cardEdit.properties = ["cardholderName": "Usagi", "number": "4111111111111111", "expMonth": "4", "expYear": "2031"]
                cardEdit.customFields = [CustomField(name: "PIN", value: "0420", kind: .hidden), CustomField(name: "Virtual", value: "true", kind: .boolean)]
                let ok = await model.createItem(.card, edit: cardEdit)
                let card = model.items.first { $0.name == "Selftest card" }
                check(ok && card?.kind == .card && card?.properties["number"] == "4111111111111111"
                      && card?.customFields.count == 2 && card?.fields.contains { $0.label == "PIN" && $0.secret } == true,
                      "create card with custom fields")
                if let card {
                    var edit = CipherEdit()
                    edit.properties = ["code": "123"]
                    edit.customFields = [CustomField(name: "PIN", value: "9999", kind: .hidden)]
                    _ = await model.updateItem(card.id, edit: edit)
                    let after = model.items.first { $0.id == card.id }
                    check(after?.properties["code"] == "123" && after?.properties["cardholderName"] == "Usagi"
                          && after?.customFields == [CustomField(name: "PIN", value: "9999", kind: .hidden)], "edit card keeps other fields")
                    await model.deleteForever(after ?? card)
                }
                var idEdit = CipherEdit(name: "Selftest identity")
                idEdit.properties = ["firstName": "Hachiware", "postalCode": "100-0001", "passportNumber": "X1234567"]
                _ = await model.createItem(.identity, edit: idEdit)
                let identity = model.items.first { $0.name == "Selftest identity" }
                check(identity?.properties["passportNumber"] == "X1234567" && identity?.username == "Hachiware", "create identity")
                if let identity { await model.deleteForever(identity) }
                let pair = SSHKeyPair.generateEd25519(comment: "selftest")
                var sshEdit = CipherEdit(name: "Selftest SSH")
                sshEdit.properties = ["privateKey": pair.privateKey, "publicKey": pair.publicKey, "keyFingerprint": pair.fingerprint]
                _ = await model.createItem(.sshKey, edit: sshEdit)
                let ssh = model.items.first { $0.name == "Selftest SSH" }
                check(ssh?.properties["publicKey"] == pair.publicKey && ssh?.username == pair.fingerprint, "create SSH key")

                // SSH agent: real ssh-add / ssh-keygen talk to it; approvals go through our hook.
                let socket = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AccountStore.appGroup)!
                    .appending(path: "t.sock")
                var asked: [String] = []
                model.sshAgent.approveOverride = { key, program in asked.append("\(program)→\(key)"); return true }
                model.sshAgent.start(at: socket)
                let env = ["SSH_AUTH_SOCK": socket.path]
                let listed = await Snapshot.tool("ssh-add", ["-L"], env: env)
                check(listed.status == 0 && listed.output.contains(pair.publicKey.split(separator: " ")[1]), "ssh-add lists the vault's SSH key")
                let pubFile = FileManager.default.temporaryDirectory.appending(path: "selftest-key.pub")
                try? Data((pair.publicKey + "\n").utf8).write(to: pubFile)
                let message = Data("signed commit\n".utf8)
                let agentSigned = await Snapshot.tool("ssh-keygen", ["-Y", "sign", "-n", "git", "-f", pubFile.path, "-q"], env: env, stdin: message)
                let signers = FileManager.default.temporaryDirectory.appending(path: "selftest-signers")
                let sigFile = FileManager.default.temporaryDirectory.appending(path: "selftest.sig")
                try? Data("usagi \(pair.publicKey)\n".utf8).write(to: signers)
                try? Data(agentSigned.output.utf8).write(to: sigFile)
                let verified = await Snapshot.tool("ssh-keygen", ["-Y", "verify", "-n", "git", "-I", "usagi", "-f", signers.path, "-s", sigFile.path],
                                         stdin: message)
                check(agentSigned.status == 0 && verified.status == 0 && asked == ["ssh-keygen→Selftest SSH"],
                      "git-style signing through the agent asks once and verifies")
                model.sshAgent.approveOverride = { _, _ in false }
                let denied = await Snapshot.tool("ssh-keygen", ["-Y", "sign", "-n", "git", "-f", pubFile.path, "-q"], env: env, stdin: message)
                check(denied.status != 0, "denied approval fails the signature")
                model.sshAgent.stop()
                model.sshAgent.approveOverride = nil
                if let ssh { await model.deleteForever(ssh) }

                // Passkey stored on a login: decoded, signable, published, preserved by edits.
                let hash = Data(repeating: 9, count: 32)
                let reg = try? Passkey.register(rpId: "webauthn.io", userName: "usagi", userHandle: Data("u-1".utf8), clientDataHash: hash)
                var pkEdit = CipherEdit(name: "Selftest passkey", username: "usagi", uri: "https://webauthn.io")
                pkEdit.passkey = reg?.credential
                _ = await model.createItem(.login, edit: pkEdit)
                var login = model.items.first { $0.name == "Selftest passkey" }
                let signed = login?.passkeys.first.flatMap { try? Passkey.assert($0, clientDataHash: hash) }
                check(login?.hasPasskey == true && signed?.credentialID == reg?.credentialID, "passkey saved, synced and signs")
                if let id = login?.id { _ = await model.updateItem(id, edit: CipherEdit(password: "changed")) }
                login = model.items.first { $0.name == "Selftest passkey" }
                check(login?.passkeys.first?.keyValue == reg?.credential.keyValue, "editing a login keeps its passkey")
                if let login { await model.deleteForever(login) }

                // Attachments: add from a file, preview a decrypted copy, delete.
                _ = await model.createItem(.secureNote, edit: CipherEdit(name: "Selftest files", notes: "x"))
                if let note = model.items.first(where: { $0.name == "Selftest files" }) {
                    let source = FileManager.default.temporaryDirectory.appending(path: "selftest 附件.txt")
                    let contents = Data("chiikawa attachment ✓\n".utf8) + Data(repeating: 7, count: 200_000)
                    try? contents.write(to: source)
                    let added = await model.addAttachments([source], to: note)
                    try? FileManager.default.removeItem(at: source)
                    let withFile = model.items.first { $0.id == note.id }
                    let file = withFile?.attachments.first
                    check(added && file?.fileName == "selftest 附件.txt" && (file?.size ?? 0) >= contents.count, "attach a file")
                    if let withFile, let file {
                        await model.previewAttachment(file, of: withFile)
                        let previewed = model.previewURL.flatMap { try? Data(contentsOf: $0) }
                        check(previewed == contents && model.previewURL?.lastPathComponent == file.fileName,
                              "download and decrypt for Quick Look")
                        await model.deleteAttachment(file, of: withFile)
                        check(model.items.first { $0.id == note.id }?.attachments.isEmpty == true, "delete attachment")
                    }
                    if let n = model.items.first(where: { $0.id == note.id }) { await model.deleteForever(n) }
                }

                // cw command line and App Intents.
                var cliEdit = CipherEdit(name: "Selftest cli", username: "cli-user", password: "cli-secret-42", totp: "JBSWY3DPEHPK3PXP")
                cliEdit.customFields = [CustomField(name: "PIN", value: "2468", kind: .hidden)]
                _ = await model.createItem(.login, edit: cliEdit)
                let cliSocket = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AccountStore.appGroup)!
                    .appending(path: "c.sock")
                var approvals: [String] = []
                model.cli.approveOverride = { approvals.append($0); return true }
                model.cli.start(at: cliSocket)
                let cw = CLIBridge.toolPath, cwEnv = ["CW_SOCKET": cliSocket.path]
                let status = await Snapshot.tool(cw, ["status"], env: cwEnv)
                let cwPassword = await Snapshot.tool(cw, ["get", "selftest cli"], env: cwEnv)
                let pin = await Snapshot.tool(cw, ["get", "Selftest cli", "--field", "PIN"], env: cwEnv)
                let cwCode = await Snapshot.tool(cw, ["code", "Selftest cli"], env: cwEnv)
                let generated = await Snapshot.tool(cw, ["generate", "--length", "32"], env: cwEnv)
                let missing = await Snapshot.tool(cw, ["get", "no-such-item-xyz"], env: cwEnv)
                check(status.output.hasPrefix("unlocked") && cwPassword.output == "cli-secret-42" && pin.output == "2468"
                      && cwCode.output.count == 6 && generated.output.count == 32 && missing.status != 0
                      && approvals.count == 3, "cw: status, get, custom field, code, generate, not found")
                model.cli.approveOverride = { _ in false }
                let refused = await Snapshot.tool(cw, ["get", "Selftest cli"], env: cwEnv)
                check(refused.status != 0 && refused.output.contains("Not approved"), "cw: refused approval reveals nothing")

                // Browser extension commands over the same socket (as Safari's handler / Chrome's host send them).
                model.cli.approveOverride = { approvals.append($0); return true }
                var confirmations: [String] = []
                var confirmAnswer = true
                model.cli.confirmOverride = { confirmations.append($0); return confirmAnswer }
                _ = await model.createItem(.login, edit: CipherEdit(name: "Selftest web", username: "web-user", password: "web-pass-1",
                                                                    uri: "https://login.chiikawa.test/signin"))
                func bridge(_ r: CLIRequest) async -> CLIResponse {
                    let path = cliSocket.path
                    return await Task.detached { BridgeClient.send(r, socket: path) }.value
                }
                let page = "https://login.chiikawa.test/signin?next=/"
                let matched = await bridge(CLIRequest(command: .match, url: page))
                let elsewhere = await bridge(CLIRequest(command: .match, url: "https://evil.example/login"))
                let webID = matched.rows?.first { $0.name == "Selftest web" }?.id ?? ""
                let filled = await bridge(CLIRequest(command: .fill, query: webID, url: page))
                let wrongSite = await bridge(CLIRequest(command: .fill, query: webID, url: "https://evil.example/login"))
                check(matched.rows?.count == 1 && matched.rows?.first?.detail == "web-user" && elsewhere.rows?.isEmpty == true
                      && filled.username == "web-user" && filled.password == "web-pass-1" && !wrongSite.ok,
                      "browser: suggestions only for the page's site, fill after approval, never on another site")
                let same = await bridge(CLIRequest(command: .save, url: page, username: "web-user", password: "web-pass-1"))
                let updated = await bridge(CLIRequest(command: .save, url: page, username: "web-user", password: "web-pass-2"))
                let added = await bridge(CLIRequest(command: .save, url: "https://new.chiikawa.test/login", username: "newbie", password: "n-1"))
                confirmAnswer = false
                let declined = await bridge(CLIRequest(command: .save, url: "https://other.chiikawa.test/", username: "x", password: "y"))
                let newItem = model.items.first { $0.host == "new.chiikawa.test" }
                check(same.value == "unchanged" && updated.value == "updated" && added.value == "saved" && declined.value == "skipped"
                      && confirmations.count == 3 && model.items.first { $0.id == webID }?.password == "web-pass-2"
                      && newItem?.username == "newbie" && !model.items.contains { $0.host == "other.chiikawa.test" },
                      "browser: save new, update changed, skip unchanged, respect Not Now")
                for item in model.items where item.name == "Selftest web" || item.host == "new.chiikawa.test" { await model.deleteForever(item) }
                model.cli.confirmOverride = nil

                model.cli.stop()
                model.cli.approveOverride = nil

                var gen = GeneratePasswordIntent()
                gen.length = 24
                let intentPassword = (try? await gen.perform())?.value
                let found = try? await VaultItemQuery().entities(matching: "selftest cli")
                var intentCode: String?
                if let entity = found?.first {
                    var codeIntent = GetOneTimeCodeIntent()
                    codeIntent.item = entity
                    intentCode = (try? await codeIntent.perform())?.value
                }
                check(intentPassword?.count == 24 && found?.count == 1 && intentCode?.count == 6,
                      "App Intents: generate, find item, get code (\(found?.count ?? -1) found)")
                if let cliItem = model.items.first(where: { $0.name == "Selftest cli" }) { await model.deleteForever(cliItem) }

                // Send: create, open it as a stranger from the copied link, delete.
                var sendDraft = SendDraft(name: "Selftest send", content: .text("hello from usagi", hidden: false),
                                          deletionDate: .now.addingTimeInterval(3_600))
                sendDraft.password = "pw"
                let sendCreated = await model.createSend(sendDraft, accountId: firstID)
                let copiedLink = NSPasteboard.general.string(forType: .string) ?? ""
                let mySend = model.sends.first { $0.name == "Selftest send" }
                var opened = ""
                if let mySend, let fragment = copiedLink.split(separator: "/").last, let material = Data(base64URL: String(fragment)),
                   let key = try? SendCrypto.key(from: material), let hash = try? SendCrypto.passwordHash("pw", keyMaterial: material) {
                    let stranger = VaultClient(environment: .selfHosted(URL(string: server)!), deviceIdentifier: UUID().uuidString)
                    let response = try? await stranger.accessSend(accessId: mySend.accessId, passwordHash: hash)
                    opened = response?.text?.text.flatMap { try? EncString($0).decryptString(with: key) } ?? ""
                }
                check(sendCreated && mySend?.hasPassword == true && copiedLink.contains("#/send/") && opened == "hello from usagi",
                      "Send: create, copy link, open as recipient")
                if let mySend { await model.deleteSend(mySend) }
                check(!model.sends.contains { $0.name == "Selftest send" }, "Send: delete")

                // Updates: Sparkle is embedded with its installer service and pointed at the release appcast.
                let info = Bundle.main.infoDictionary ?? [:]
                let sparkle = Bundle.main.privateFrameworksURL?.appending(path: "Sparkle.framework")
                check(FileManager.default.fileExists(atPath: sparkle?.path ?? "")
                      && (info["SUFeedURL"] as? String)?.hasSuffix("/releases/latest/download/appcast.xml") == true
                      && info["SUEnableInstallerLauncherService"] as? Bool == true
                      && info["SUEnableAutomaticChecks"] as? Bool == false,
                      "updates: Sparkle embedded, appcast feed, installer service, checks opt-in")

                // The AutoFill extension's flow, in-process: register a passkey for a site, then sign in with it.
                let ext = AutoFillState()
                var registered: ASPasskeyRegistrationCredential?
                var asserted: ASPasskeyAssertionCredential?
                ext.completeRegistration = { registered = $0 }
                ext.completeAssertion = { asserted = $0 }
                ext.begin(passkey: .init(rpId: "passkeys.example", clientDataHash: hash, userName: "usagi",
                                         userHandle: Data("u-2".utf8), algorithms: [-7]), registering: true)
                ext.selectedAccountID = firstID
                await ext.unlock(password: password)
                await ext.register(accountId: firstID, itemId: nil)
                check(registered != nil && ext.error == nil, "AutoFill: unlock and save a new passkey to the server \(ext.error ?? "")")
                let signIn = AutoFillState()
                signIn.completeAssertion = { asserted = $0 }
                signIn.begin(passkey: .init(rpId: "passkeys.example", clientDataHash: hash), registering: false)
                signIn.selectedAccountID = firstID
                await signIn.unlock(password: password)
                if let c = signIn.passkeyCandidates.first { await signIn.signIn(c.item, c.passkey) }
                check(asserted != nil && asserted?.credentialID == registered?.credentialID
                      && asserted?.userHandle == Data("u-2".utf8), "AutoFill: sign in with that passkey from the cached vault")
                try? await model.refresh()
                if let made = model.items.first(where: { $0.passkeys.first?.rpId == "passkeys.example" }) { await model.deleteForever(made) }
            }

            // Second account: merged list, per-account lock and unlock.
            var secondID: String?
            if let (email2, password2) = second {
                model.beginAddAccount()
                model.serverKind = .selfHosted
                model.serverURL = server
                model.email = email2
                await model.login(password: password2)
                let id2 = SavedAccount.makeID(serverKind: "selfHosted", serverURL: server, email: email2)
                secondID = id2
                let fromFirst = model.items.filter { $0.accountId == firstID }.count
                let fromSecond = model.items.filter { $0.accountId == id2 }.count
                check(model.accounts.count == 2 && model.sessions.count == 2 && fromFirst == count && fromSecond > 0,
                      "second account merged (\(fromFirst) + \(fromSecond) items)")
                let created2 = await model.createItem(.secureNote, edit: CipherEdit(name: "Second-account note", notes: "x"), accountId: id2)
                let note = model.items.first { $0.name == "Second-account note" }
                check(created2 && note?.accountId == id2, "new item goes to the chosen account")
                if let note { await model.deleteForever(note) }

                // Import / export: account 1's vault, password-protected, imported into account 2; compare; clean up.
                if let s1 = model.session(for: firstID), let s2 = model.session(for: id2) {
                    do {
                        let mine = model.items.filter { $0.accountId == firstID && !$0.isDeleted && $0.organizationId == nil }
                        let file = try s1.export(.encryptedJSON, filePassword: "selftest-file").data
                        check(!String(decoding: file, as: UTF8.self).contains(mine.first?.name ?? "\u{0}"), "protected export hides the vault")
                        let preview = try s2.previewImport(file, password: "selftest-file")
                        let beforeItems = Set(model.items.filter { $0.accountId == id2 }.map(\.id))
                        let beforeFolders = Set(s2.folders.map(\.id))
                        try await s2.importItems(preview.items, folders: preview.folders)
                        let imported = model.items.filter { $0.accountId == id2 && !beforeItems.contains($0.id) }
                        func identical(_ a: VaultItem, _ b: VaultItem) -> Bool {
                            guard a.name == b.name, a.kind == b.kind, a.username == b.username, a.password == b.password else { return false }
                            guard a.notes == b.notes, a.totp?.code() == b.totp?.code() else { return false }
                            return a.customFields == b.customFields && a.properties == b.properties
                        }
                        let same = imported.count == mine.count && imported.allSatisfy { copy in mine.contains { identical($0, copy) } }
                        check(same, "export → import round trip: \(imported.count) of \(mine.count) items identical")
                        for item in imported { await model.deleteForever(item) }
                        for folder in s2.folders where !beforeFolders.contains(folder.id) { try? await s2.deleteFolder(folder.id) }

                        let csv = try VaultImport.preview(try s1.export(.csv).data)
                        let csvKinds: Set<VaultItem.Kind> = [.login, .note]
                        let expected = mine.filter { csvKinds.contains($0.kind) }.count
                        check(csv.items.count == expected, "CSV export holds every login and note (\(csv.items.count))")
                    } catch {
                        check(false, "export → import round trip: \(error)")
                    }
                }
                model.lock(id2)
                check(model.isUnlocked && model.sessions.count == 1 && !model.items.contains { $0.accountId == id2 },
                      "lock one account, keep the other open")
                await model.unlock(password: password2, accountId: id2)
                check(model.sessions.count == 2 && model.items.contains { $0.accountId == id2 }, "unlock that account again")
            }

            // Custom environment: no server URL, explicit per-service URLs.
            model.beginAddAccount()
            model.serverKind = .selfHosted
            model.serverURL = "http://example.com"
            model.email = email
            await model.login(password: password)
            check(model.errorMessage?.contains("https://") == true, "public http:// server rejected")
            model.serverURL = ""
            model.customAPI = server + "/api"
            model.customIdentity = server + "/identity"
            model.customNotifications = server + "/notifications"
            model.errorMessage = nil
            await model.login(password: password)
            let customAccount = model.accounts.first { $0.customURLs != nil }
            check(customAccount != nil && model.session(for: customAccount!.id)?.items.isEmpty == false
                  && model.session(for: customAccount!.id)?.environment.map { if case .custom = $0 { true } else { false } } == true,
                  "log in through custom API / Identity URLs, saved with the account")
            if let customAccount { model.logOut(customAccount.id) }

            // Single sign-on (dev stack: dex + SSO-enabled Vaultwarden next door on :18881).
            let ssoServer = server.replacingOccurrences(of: ":18880", with: ":18881")
            if ssoServer != server,
               (try? await URLSession.shared.data(from: URL(string: ssoServer + "/identity/sso/prevalidate?domainHint=x")!))
                .map({ ($0.1 as? HTTPURLResponse)?.statusCode == 200 }) == true {
                model.beginAddAccount()
                model.serverKind = .selfHosted
                model.serverURL = ssoServer
                model.ssoAuthenticator = { url in try await HeadlessIdP.signIn(url, login: email, password: password) }
                await model.loginWithSSO(identifier: "chiikawarden")
                check(model.phase.id == AppModel.Phase.ssoPassword.id && model.email == email,
                      "SSO: identity provider sign-in, then asks for the master password \(model.errorMessage ?? "")")
                await model.completeSSO(password: "wrong")
                check(model.phase.id == AppModel.Phase.ssoPassword.id && model.errorMessage != nil, "SSO: wrong master password refused")
                await model.completeSSO(password: password)
                let ssoAccount = model.accounts.first { $0.serverURL == ssoServer }
                check(ssoAccount != nil && model.session(for: ssoAccount!.id)?.items.isEmpty == false && AccountStore.refreshToken(ssoAccount!.id) != nil,
                      "SSO: vault unlocked, account and session saved")
                if let ssoAccount { model.logOut(ssoAccount.id) }
                model.ssoAuthenticator = WebAuthentication.run
            } else {
                print("SKIP SSO (no SSO server at \(ssoServer))")
            }

            model.lock()
            check(model.phase.id == AppModel.Phase.locked.id && model.items.isEmpty, "lock clears vault, shows unlock")
            check(!FileManager.default.fileExists(atPath: AttachmentFiles.root.path) && model.previewURL == nil,
                  "lock wipes decrypted attachment copies")

            let fresh = AppModel() // simulates relaunch
            check(fresh.phase.id == AppModel.Phase.locked.id && fresh.accounts.count == (second == nil ? 1 : 2),
                  "relaunch starts locked with \(fresh.accounts.count) saved account(s)")
            fresh.unlockTargetID = firstID
            await fresh.unlock(password: "definitely-wrong")
            check(!fresh.isUnlocked && fresh.errorMessage != nil, "wrong password rejected offline")
            await fresh.unlock(password: password)
            check(fresh.isUnlocked && fresh.items.count == count, "offline unlock restores \(fresh.items.count) items from cache")
            try? await Task.sleep(for: .seconds(3))
            check(fresh.lastSynced != nil, "session resumed with refresh token and re-synced")

            // Another device changes the vault → live notification → automatic re-sync.
            let before = fresh.lastSynced ?? .distantPast
            if let url = URL(string: server) {
                let other = VaultClient(environment: .selfHosted(url), deviceIdentifier: UUID().uuidString.lowercased())
                if let key = try? await other.login(email: email, password: password),
                   let folder = try? await other.createFolder(encryptedName: EncString.encrypt(Data("selftest".utf8), with: key).description) {
                    try? await Task.sleep(for: .seconds(4))
                    check((fresh.lastSynced ?? .distantPast) > before, "live sync picked up a change from another device")
                    try? await other.deleteFolder(id: folder)
                } else {
                    check(false, "second device could not change the vault")
                }
            }

            if let secondID {
                fresh.logOut(secondID)
                check(fresh.accounts.count == 1 && AccountStore.load(secondID) == nil && fresh.isUnlocked,
                      "log out one account, the other stays")
            }
            fresh.logOut(firstID)
            check(AccountStore.load(firstID) == nil && AccountStore.refreshToken(firstID) == nil && fresh.phase.id == AppModel.Phase.login.id,
                  "log out erases account and token")
            print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
    }
}
#endif

/// Plays a browser through dex's password form, for the SSO self-test.
enum HeadlessIdP {
    final class Browser: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        var callback: URL?
        lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            if request.url?.scheme == "bitwarden" { callback = request.url; return nil }
            return request
        }
    }

    static func signIn(_ url: URL, login: String, password: String) async throws -> URL {
        let browser = Browser()
        let (pageData, pageResponse) = try await browser.session.data(from: url)
        let page = String(decoding: pageData, as: UTF8.self)
        guard var formURL = pageResponse.url else { throw URLError(.badServerResponse) }
        if let range = page.range(of: #"action="([^"]*)""#, options: .regularExpression) {
            let action = String(page[range]).dropFirst(8).dropLast().replacingOccurrences(of: "&amp;", with: "&")
            formURL = URL(string: action, relativeTo: formURL)?.absoluteURL ?? formURL
        }
        var post = URLRequest(url: formURL)
        post.httpMethod = "POST"
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        post.httpBody = Data("login=\(login.addingPercentEncoding(withAllowedCharacters: allowed)!)&password=\(password.addingPercentEncoding(withAllowedCharacters: allowed)!)".utf8)
        _ = try? await browser.session.data(for: post)
        guard let callback = browser.callback else { throw URLError(.userAuthenticationRequired) }
        return callback
    }
}
