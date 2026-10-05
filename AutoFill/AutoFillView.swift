import AppKit
import AuthenticationServices
import ChiikawaCrypto
import Observation
import SwiftUI

@MainActor @Observable
final class AutoFillState {
    enum Mode { case password, oneTimeCode }

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

    var completePassword: (String, String) -> Void = { _, _ in }
    var completeCode: (String) -> Void = { _ in }
    var cancel: () -> Void = {}

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
        let keys = await AccountStore.unlockAllWithTouchID(accounts.map(\.id), reason: String(localized: "fill a password"))
        if !keys.isEmpty { open(with: keys) }
    }

    private func open(with keys: [String: SymmetricKeyPair]) {
        let vaults = keys.compactMap { id, key in
            AccountStore.loadCache(id).flatMap { try? VaultDecoder.decode($0, userKey: key, accountId: id) }
        }
        guard !vaults.isEmpty else {
            error = String(localized: "Open Chiikawarden once to download your vault.")
            return
        }
        items = vaults.flatMap(\.items).filter { !$0.isDeleted && $0.kind == .login }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        unlocked = true
        error = nil
        // A QuickType pick fills immediately after unlock.
        if let preselect, let item = items.first(where: { $0.id == preselect }) { fill(item) }
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
            } else if state.unlocked {
                PickList(state: state)
            } else {
                UnlockPane(state: state)
            }
        }
        .frame(width: 440, height: 500)
        .tint(Color(red: 0.25, green: 0.42, blue: 0.94))
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
            Text("Unlock to fill").font(.system(size: 17, weight: .semibold))
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
            SecureField("Master password", text: $password)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($focused)
                .frame(width: 280)
                .onSubmit { Task { await state.unlock(password: password) } }
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
            Text(mode == .password ? "Fill" : "Fill code").font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(selected ? .white : .primary)
        .padding(.horizontal, 10).frame(height: 44)
        .background(selected ? Color(red: 0.25, green: 0.42, blue: 0.94) : .clear, in: .rect(cornerRadius: 9))
        .contentShape(.rect)
    }
}
