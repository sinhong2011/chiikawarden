import Foundation
import LocalAuthentication
import Observation
import SSHAgent

/// Serves the unlocked vault's SSH keys to `ssh`, `git` and friends. Every signature needs Touch ID
/// (or the Mac's password); an approval can optionally be remembered briefly per key and program.
@MainActor @Observable
final class SSHAgentService {
    /// `~/Library/Group Containers/<group>/agent.sock`. Kept short: a socket path must fit in 104 bytes.
    static var defaultSocket: URL {
        (FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AccountStore.appGroup)
            ?? FileManager.default.temporaryDirectory).appending(path: "agent.sock")
    }

    private(set) var isRunning = false
    private(set) var lastError: String?
    /// Last few uses, newest first, for Settings.
    private(set) var recent: [(date: Date, key: String, program: String, allowed: Bool)] = []

    private var server: SSHAgentServer?
    private var parsed: [String: (pem: String, key: SSHPrivateKey)] = [:]
    private var approvedUntil: [String: Date] = [:]
    private weak var model: AppModel?
    /// Self-test hook: skip the Touch ID prompt.
    var approveOverride: ((String, String) -> Bool)?

    init(model: AppModel) { self.model = model }

    func start(at socket: URL = defaultSocket) {
        guard server == nil else { return }
        let server = SSHAgentServer(
            socketURL: socket,
            identities: { [weak self] in await self?.identities() ?? [] },
            approve: { [weak self] identity, peer in await self?.approve(identity, peer) ?? false })
        do {
            try server.start()
            self.server = server
            isRunning = true
            lastError = nil
        } catch SSHAgentServer.Failure.pathTooLong {
            lastError = String(localized: "Couldn't start the SSH agent: the socket path is longer than macOS allows (104 bytes). This happens with very long user names.")
        } catch {
            lastError = String(localized: "Couldn't start the SSH agent: \(String(describing: error))")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
    }

    var socketPath: String { server?.socketURL.path ?? Self.defaultSocket.path }

    /// Forget approvals and parsed keys (on lock).
    func reset() {
        parsed = [:]
        approvedUntil = [:]
    }

    // MARK: Agent callbacks

    /// SSH key items from every unlocked account. Empty while locked.
    private func identities() -> [SSHAgentServer.Identity] {
        guard let model else { return [] }
        return model.items.filter { $0.kind == .sshKey && !$0.isDeleted && !$0.isArchived }.compactMap { item in
            guard let pem = item.properties["privateKey"], !pem.isEmpty else { return nil }
            if let cached = parsed[item.id], cached.pem == pem {
                return SSHAgentServer.Identity(id: item.id, name: item.name, key: cached.key)
            }
            guard let key = try? SSHPrivateKey(pem: pem) else { return nil }
            parsed[item.id] = (pem, key)
            return SSHAgentServer.Identity(id: item.id, name: item.name, key: key)
        }
    }

    private func approve(_ identity: SSHAgentServer.Identity, _ peer: SSHAgentServer.Peer) async -> Bool {
        let grant = "\(identity.id)|\(peer.processName)"
        if let until = approvedUntil[grant], until > .now { return log(identity, peer, true) }
        let allowed: Bool
        if let approveOverride {
            allowed = approveOverride(identity.name, peer.processName)
        } else {
            let context = LAContext()
            context.localizedCancelTitle = String(localized: "Deny")
            let reason = String(localized: "allow “\(peer.processName)” to sign with the SSH key “\(identity.name)”")
            allowed = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true
        }
        let window = UserDefaults.standard.integer(forKey: Pref.sshApprovalSeconds)
        if allowed, window > 0 { approvedUntil[grant] = .now.addingTimeInterval(TimeInterval(window)) }
        model?.noteActivity()
        return log(identity, peer, allowed)
    }

    private func log(_ identity: SSHAgentServer.Identity, _ peer: SSHAgentServer.Peer, _ allowed: Bool) -> Bool {
        recent.insert((.now, identity.name, peer.processName, allowed), at: 0)
        if recent.count > 8 { recent.removeLast() }
        return allowed
    }
}
