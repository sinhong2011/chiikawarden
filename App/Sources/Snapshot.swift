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
            render(GeneratorView(onUse: { _ in }).environment(vault).tint(.brand).background(Color.windowBase),
                   size: CGSize(width: 340, height: 420), appearance: appearance,
                   to: dir.appending(path: "generator-\(name).png"))
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
                  hasPasskey: true,
                  passkeys: [PasskeyCredential(credentialId: "demo", keyValue: "", rpId: "github.com", userName: "usagi",
                                               creationDate: Date(timeIntervalSince1970: 1_780_000_000))]),
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
            check(model.isUnlocked && !model.items.isEmpty, "login + sync (\(model.items.count) items)")
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

            model.lock()
            check(model.phase.id == AppModel.Phase.locked.id && model.items.isEmpty, "lock clears vault, shows unlock")

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
