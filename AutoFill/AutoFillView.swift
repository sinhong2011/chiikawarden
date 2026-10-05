import AppKit
import AuthenticationServices
import ChiikawaCrypto
import Observation
import SwiftUI
import VaultwardenAPI

@MainActor @Observable
final class AutoFillState {
    enum Mode { case password, oneTimeCode, passkey, registration }

    /// A WebAuthn request from the system (sign-in or registration).
    struct PasskeyRequest {
        var rpId: String
        var clientDataHash: Data
        /// Sign-in: credentials the site accepts (empty = any). Registration: ones it already has.
        var credentialIDs: [Data] = []
        var userName = ""
        var userHandle = Data()
        var algorithms: [Int] = []
    }

    var mode: Mode = .password
    var domains: [String] = []
    var preselect: String?
    var items: [VaultItem] = []
    var unlocked = false
    var busy = false
    var error: String?
    var accounts = AccountStore.accounts()
    /// Account the master-password field unlocks (when there are several).
    var selectedAccountID = AccountStore.accounts().first?.id
    var touchIDEnabled = AccountStore.accounts().contains { AccountStore.isTouchIDEnabled($0.id) }
    var email: String {
        get { accounts.first { $0.id == selectedAccountID }?.email ?? storedEmail }
        set { storedEmail = newValue }
    }
    private var storedEmail = ""
    var hasAccount = !AccountStore.accounts().isEmpty

    var passkeyRequest: PasskeyRequest?
    /// Accounts opened in this request, for writing a new passkey back.
    private(set) var opened: [String: (key: SymmetricKeyPair, vault: DecodedVault)] = [:]
    var openedAccounts: [SavedAccount] { accounts.filter { opened[$0.id] != nil } }

    var completePassword: (String, String) -> Void = { _, _ in }
    var completeCode: (String) -> Void = { _ in }
    var completeAssertion: (ASPasskeyAssertionCredential) -> Void = { _ in }
    var completeRegistration: (ASPasskeyRegistrationCredential) -> Void = { _ in }
    var cancel: () -> Void = {}
    var fail: (ASExtensionError.Code) -> Void = { _ in }

    enum SaveError: LocalizedError {
        case signedOut, vaultOutOfDate
        var errorDescription: String? {
            switch self {
            case .signedOut: String(localized: "Open Chiikawarden and sign in to this account again.")
            case .vaultOutOfDate: String(localized: "Open Chiikawarden once to refresh your vault.")
            }
        }
    }

    func begin(passkey request: PasskeyRequest, registering: Bool, preselect: String? = nil) {
        mode = registering ? .registration : .passkey
        passkeyRequest = request
        self.preselect = preselect
        domains = [request.rpId.lowercased()]
    }

    func begin(mode: Mode, services: [ASCredentialServiceIdentifier], preselect: String?) {
        self.mode = mode
        self.preselect = preselect
        domains = services.compactMap { service in
            switch service.type {
            case .domain: service.identifier.lowercased()
            default: URL(string: service.identifier)?.host()?.lowercased() ?? service.identifier.lowercased()
            }
        }
    }

    func unlock(password: String) async {
        guard let id = selectedAccountID else { return }
        busy = true
        defer { busy = false }
        let key = await Task.detached(priority: .userInitiated) { AccountStore.unlock(id, password: password) }.value
        guard let key else { error = String(localized: "Wrong master password."); return }
        open(with: [id: key])
    }

    /// One prompt opens every account that has Touch ID turned on.
    func unlockWithTouchID() async {
        let reason = switch mode {
        case .passkey: String(localized: "sign in with a passkey")
        case .registration: String(localized: "save a passkey")
        default: String(localized: "fill a password")
        }
        let keys = await AccountStore.unlockAllWithTouchID(accounts.map(\.id), reason: reason)
        if !keys.isEmpty { open(with: keys) }
    }

    private func open(with keys: [String: SymmetricKeyPair]) {
        for (id, key) in keys {
            if let vault = AccountStore.loadCache(id).flatMap({ try? VaultDecoder.decode($0, userKey: key, accountId: id) }) {
                opened[id] = (key, vault)
            }
        }
        let vaults = opened.values.map(\.vault)
        guard !vaults.isEmpty else {
            error = String(localized: "Open Chiikawarden once to download your vault.")
            return
        }
        items = vaults.flatMap(\.items).filter { !$0.isDeleted && $0.kind == .login }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        unlocked = true
        error = nil
        if mode == .registration, let request = passkeyRequest,
           items.contains(where: { $0.passkeys.contains { pk in pk.rawId.map(request.credentialIDs.contains) == true } }) {
            fail(.matchedExcludedCredential) // the site already has one of our passkeys for this account
            return
        }
        // A QuickType pick fills immediately after unlock.
        if let preselect, let item = items.first(where: { $0.id == preselect }) {
            if mode == .passkey, let pk = passkeyCandidates.first(where: { $0.item.id == preselect }) {
                Task { await signIn(pk.item, pk.passkey) }
            } else if mode != .passkey {
                fill(item)
            }
        }
    }

    // MARK: Passkeys

    /// Passkeys for the requesting site that it will accept.
    var passkeyCandidates: [(item: VaultItem, passkey: PasskeyCredential)] {
        guard let request = passkeyRequest else { return [] }
        return items.flatMap { item in item.passkeys.map { (item, $0) } }.filter { _, pk in
            pk.rpId.caseInsensitiveCompare(request.rpId) == .orderedSame
                && (request.credentialIDs.isEmpty || pk.rawId.map(request.credentialIDs.contains) == true)
        }
    }

    func signIn(_ item: VaultItem, _ passkey: PasskeyCredential) async {
        guard let request = passkeyRequest else { return }
        do {
            let a = try Passkey.assert(passkey, clientDataHash: request.clientDataHash)
            if a.counter != passkey.counter {
                // Keep a counting authenticator's counter moving forward for the next sign-in.
                var edit = CipherEdit()
                edit.passkeyCounter = (passkey.credentialId, a.counter)
                try? await write(edit, accountId: item.accountId, itemId: item.id)
            }
            completeAssertion(ASPasskeyAssertionCredential(userHandle: a.userHandle, relyingParty: passkey.rpId,
                                                           signature: a.signature, clientDataHash: request.clientDataHash,
                                                           authenticatorData: a.authenticatorData, credentialID: a.credentialID))
        } catch {
            self.error = String(localized: "This passkey can't be used here.")
        }
    }

    /// Logins in `accountId` a new passkey could be added to.
    func registrationTargets(_ accountId: String?) -> [VaultItem] {
        items.filter { $0.accountId == accountId && matches($0) }
    }

    /// Creates the passkey, saves it to the server (new login, or replacing `itemId`'s passkey), then answers the site.
    func register(accountId: String, itemId: String?) async {
        guard let request = passkeyRequest else { return }
        busy = true
        defer { busy = false }
        do {
            let reg = try Passkey.register(rpId: request.rpId, rpName: request.rpId, userName: request.userName,
                                           userHandle: request.userHandle, clientDataHash: request.clientDataHash,
                                           algorithms: request.algorithms)
            var edit = CipherEdit()
            if itemId == nil {
                edit = CipherEdit(name: request.rpId, username: request.userName, uri: "https://" + request.rpId)
            }
            edit.passkey = reg.credential
            try await write(edit, accountId: accountId, itemId: itemId)
            completeRegistration(ASPasskeyRegistrationCredential(relyingParty: request.rpId, clientDataHash: request.clientDataHash,
                                                                 credentialID: reg.credentialID, attestationObject: reg.attestationObject))
        } catch Passkey.Failure.unsupportedAlgorithm {
            error = String(localized: "This site needs a key type Chiikawarden can't create.")
        } catch {
            self.error = String(localized: "Couldn't save the passkey: \(error.localizedDescription)")
        }
    }

    /// Writes an edit through the account's server, then refreshes the shared cache and QuickType list.
    private func write(_ edit: CipherEdit, accountId: String, itemId: String?) async throws {
        guard let (key, vault) = opened[accountId], let account = AccountStore.load(accountId),
              let environment = account.environment else { throw SaveError.vaultOutOfDate }
        guard let token = AccountStore.refreshToken(accountId) else { throw SaveError.signedOut }
        let client = Connection.makeClient(environment)
        await client.restore(refreshToken: token)
        AccountStore.setRefreshToken(try await client.refreshAccessToken(), accountId)
        if let itemId {
            guard let raw = vault.rawCiphers[itemId], let cache = AccountStore.loadCache(accountId),
                  let cipher = try SyncResponse.decode(cache).ciphers.first(where: { $0.id == itemId }),
                  let itemKey = vault.keyring.key(for: cipher) else { throw SaveError.vaultOutOfDate }
            try await client.updateCipher(id: itemId, CipherEditor.updatedCipher(raw: raw, edit: edit, key: itemKey))
        } else {
            _ = try await client.createCipher(CipherEditor.newCipher(kind: .login, edit: edit, key: key))
        }
        let data = try await client.syncData()
        AccountStore.saveCache(data, accountId)
        if let fresh = try? VaultDecoder.decode(data, userKey: key, accountId: accountId) {
            opened[accountId] = (key, fresh)
            AutoFillIdentities.publish(opened.values.flatMap(\.vault.items))
        }
    }

    func matches(_ item: VaultItem) -> Bool {
        guard let host = item.host?.lowercased() else { return false }
        return domains.contains { d in host == d || host.hasSuffix("." + d) || d.hasSuffix("." + host) }
    }

    func fill(_ item: VaultItem) {
        switch mode {
        case .password:
            guard let password = item.password else { return }
            completePassword(item.username ?? "", password)
        case .oneTimeCode:
            guard let totp = item.totp else { return }
            completeCode(totp.code())
        case .passkey:
            if let pk = passkeyCandidates.first(where: { $0.item.id == item.id }) { Task { await signIn(pk.item, pk.passkey) } }
        case .registration:
            break
        }
    }
}

struct AutoFillView: View {
    @Bindable var state: AutoFillState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "key.viewfinder").font(.system(size: 16, weight: .semibold)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Chiikawarden").font(.system(size: 13, weight: .semibold))
                    Text(verbatim: state.domains.first ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { state.cancel() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()

            if !state.hasAccount {
                ContentUnavailableView("Not signed in", systemImage: "person.crop.circle.badge.questionmark",
                                       description: Text("Open Chiikawarden and log in first."))
            } else if state.unlocked && state.mode == .registration {
                RegisterPane(state: state)
            } else if state.unlocked && state.mode == .passkey {
                PasskeyList(state: state)
            } else if state.unlocked {
                PickList(state: state)
            } else {
                UnlockPane(state: state)
            }
        }
        .frame(width: 440, height: 500)
        .tint(Color(nsColor: .chiikawardenBrand))
    }
}

private struct UnlockPane: View {
    @Bindable var state: AutoFillState
    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(.secondary)
            Group {
                switch state.mode {
                case .passkey: Text("Unlock to sign in")
                case .registration: Text("Unlock to save passkey")
                default: Text("Unlock to fill")
                }
            }
            .font(.system(size: 17, weight: .semibold))
            if state.accounts.count > 1 {
                Picker("Account", selection: $state.selectedAccountID) {
                    ForEach(state.accounts) { Text(verbatim: "\($0.email) · \($0.serverSummary)").tag(String?.some($0.id)) }
                }
                .labelsHidden()
                .frame(width: 280)
            } else {
                Text(verbatim: state.email).foregroundStyle(.secondary)
            }
            if state.touchIDEnabled {
                Button { Task { await state.unlockWithTouchID() } } label: {
                    Label("Unlock with Touch ID", systemImage: "touchid")
                }
                .controlSize(.large)
            }
            PasswordField(title: "Master password", text: $password, isFocused: $focused.wrappedBinding) {
                Task { await state.unlock(password: password) }
            }
            .frame(width: 280)
            if let error = state.error {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
            }
            Button {
                Task { await state.unlock(password: password) }
            } label: {
                HStack { if state.busy { ProgressView().controlSize(.small) }; Text("Unlock") }.frame(width: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(password.isEmpty || state.busy)
            Spacer()
        }
        .onAppear {
            focused = true
            if state.touchIDEnabled { Task { await state.unlockWithTouchID() } }
        }
    }
}

private struct PickList: View {
    @Bindable var state: AutoFillState
    @State private var query = ""
    @State private var index = 0

    private var candidates: [VaultItem] {
        let usable = state.items.filter { state.mode == .password ? $0.password != nil : $0.totp != nil }
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return usable.filter(state.matches) }
        return usable.filter {
            $0.name.localizedCaseInsensitiveContains(q) || ($0.username?.localizedCaseInsensitiveContains(q) ?? false)
                || ($0.host?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search vault", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
                .onKeyPress(.downArrow) { index = min(index + 1, max(candidates.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                .onSubmit { if candidates.indices.contains(index) { state.fill(candidates[index]) } }
                .onChange(of: query) { index = 0 }
            if candidates.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No logins for this site" : "No results",
                                       systemImage: "magnifyingglass",
                                       description: query.isEmpty ? Text("Search to fill from any item.") : nil)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { i, item in
                            Row(item: item, mode: state.mode, selected: i == index)
                                .onTapGesture { state.fill(item) }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { state.fill(item) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}

private struct Row: View {
    let item: VaultItem
    let mode: AutoFillState.Mode
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(item.name.prefix(1).uppercased())
                .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(selected ? Color.white.opacity(0.22) : Color.secondary, in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(verbatim: item.username ?? item.host ?? "").font(.system(size: 11)).foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
            }
            Spacer()
            Group {
                switch mode {
                case .oneTimeCode: Text("Fill code")
                case .passkey: Text("Sign In")
                default: Text("Fill")
                }
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(selected ? .white : .primary)
        .padding(.horizontal, 10).frame(height: 44)
        .background(selected ? Color(nsColor: .chiikawardenBrand) : .clear, in: .rect(cornerRadius: 9))
        .contentShape(.rect)
    }
}

/// Passkeys the site will accept; Return signs in with the highlighted one.
private struct PasskeyList: View {
    @Bindable var state: AutoFillState
    @State private var index = 0

    var body: some View {
        let candidates = state.passkeyCandidates
        VStack(spacing: 0) {
            if candidates.isEmpty {
                ContentUnavailableView("No passkeys for this site", systemImage: "person.badge.key",
                                       description: Text("Passkeys you save with Chiikawarden appear here."))
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(candidates.enumerated()), id: \.element.passkey.credentialId) { i, c in
                            Row(item: VaultItem(id: c.item.id, name: c.item.name, username: c.passkey.userName ?? c.item.username,
                                                host: c.passkey.rpId, password: nil, totp: nil, notes: nil, favorite: false),
                                mode: .passkey, selected: i == index)
                                .onTapGesture { Task { await state.signIn(c.item, c.passkey) } }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { Task { await state.signIn(c.item, c.passkey) } }
                        }
                    }
                    .padding(8)
                }
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { index = min(index + 1, candidates.count - 1); return .handled }
                .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                .onKeyPress(.return) {
                    if candidates.indices.contains(index) { Task { await state.signIn(candidates[index].item, candidates[index].passkey) } }
                    return .handled
                }
            }
            if let error = state.error {
                Text(verbatim: error).font(.caption).foregroundStyle(.red).padding(10)
            }
        }
    }
}

/// Where to save a new passkey: a new login, or an existing login for the site.
struct RegisterPane: View {
    @Bindable var state: AutoFillState
    @State private var accountId: String?
    @State private var target: String? // nil = new login

    var body: some View {
        let request = state.passkeyRequest
        let targets = state.registrationTargets(accountId)
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 30)).foregroundStyle(.tint)
                    .frame(width: 60, height: 60)
                    .background(.tint.opacity(0.12), in: .rect(cornerRadius: 16, style: .continuous))
                Text("Save a passkey").font(.system(size: 17, weight: .semibold))
                Text(verbatim: "\(request?.userName ?? "") · \(request?.rpId ?? "")")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.top, 22).padding(.bottom, 14)

            Form {
                if state.openedAccounts.count > 1 {
                    Picker("Account", selection: $accountId) {
                        ForEach(state.openedAccounts) { Text(verbatim: $0.email).tag(String?.some($0.id)) }
                    }
                }
                Picker("Save to", selection: $target) {
                    Label("New login", systemImage: "plus.circle").tag(String?.none)
                    ForEach(targets) { item in
                        Text(verbatim: "\(item.name) — \(item.username ?? "")").tag(String?.some(item.id))
                    }
                }
                .pickerStyle(.inline)
                if let target, targets.first(where: { $0.id == target })?.hasPasskey == true {
                    Label("This replaces the passkey already saved on that login.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let error = state.error {
                Text(verbatim: error).font(.caption).foregroundStyle(.red).padding(.horizontal, 16)
            }
            HStack {
                Spacer()
                Button {
                    guard let accountId else { return }
                    Task { await state.register(accountId: accountId, itemId: target) }
                } label: {
                    HStack { if state.busy { ProgressView().controlSize(.small) }; Text("Save Passkey") }.frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(accountId == nil || state.busy)
            }
            .padding(14)
        }
        .onAppear { accountId = accountId ?? state.openedAccounts.first?.id }
        .onChange(of: accountId) { target = nil }
    }
}
