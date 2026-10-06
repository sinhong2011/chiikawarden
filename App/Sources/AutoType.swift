import AppKit
import SSHAgent

/// Typing a login into another app, through the bundled helper (Triwarden Auto-Type): only the helper holds
/// Accessibility, so Triwarden itself stays sandboxed. The helper starts on first use and quits with us.
enum AutoType {
    typealias Step = AutoTypeProtocol.Request.Step

    enum Outcome { case typed, needsPermission, failed }

    static var helperURL: URL { Bundle.main.bundleURL.appending(path: "Contents/Library/Helpers/Triwarden Auto-Type.app") }

    private static var socketPath: String? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AccountStore.appGroup)?
            .appending(path: AutoTypeProtocol.socketName).path
    }

    /// Types `steps` into the app `pid` (brought forward first). Without Accessibility for the helper yet, macOS's
    /// prompt is shown and the caller falls back to the clipboard.
    static func type(_ steps: [Step], into pid: pid_t) async -> Outcome {
        guard let reply = await send(.init(action: .type, pid: pid, steps: steps)) else { return .failed }
        switch reply.failure {
        case nil: return .typed
        case .permission:
            _ = await send(.init(action: .askPermission))
            return .needsPermission
        default: return .failed
        }
    }

    /// Whether the helper may type (Accessibility allowed); starts it to find out. nil when it doesn't answer.
    static func isAllowed() async -> Bool? {
        guard let reply = await send(.init(action: .status)), reply.failure == nil else { return nil }
        return reply.trusted
    }

    /// Shows macOS's Accessibility prompt for the helper.
    static func askPermission() async { _ = await send(.init(action: .askPermission)) }

    // MARK: Talking to the helper

    private static func send(_ request: AutoTypeProtocol.Request) async -> AutoTypeProtocol.Response? {
        guard let path = socketPath, let body = try? JSONEncoder().encode(request) else { return nil }
        if let reply = await exchange(path, body) { return reply }
        guard await launchHelper() else { return nil }
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(50))
            if let reply = await exchange(path, body) { return reply }
        }
        return nil
    }

    private static func exchange(_ path: String, _ body: Data) async -> AutoTypeProtocol.Response? {
        await Task.detached {
            guard let fd = FramedSocketServer.connect(to: path) else { return nil }
            defer { close(fd) }
            guard FramedSocketServer.writeFrame(fd, body), let data = FramedSocketServer.readFrame(fd) else { return nil }
            return try? JSONDecoder().decode(AutoTypeProtocol.Response.self, from: data)
        }.value
    }

    @MainActor private static func launchHelper() async -> Bool {
        guard FileManager.default.fileExists(atPath: helperURL.path) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.arguments = ["--parent", String(ProcessInfo.processInfo.processIdentifier)]
        return (try? await NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration)) != nil
    }
}

extension AppModel {
    /// Types into the app the palette was called from; if that can't happen (no permission yet, or the helper
    /// is missing), copies `fallback` instead and goes back there so it can be pasted.
    func autoType(_ steps: [AutoType.Step], into context: ForegroundContext, fallback: (value: String, label: String)?) {
        Task {
            let outcome = await AutoType.type(steps, into: context.pid)
            noteActivity()
            guard outcome != .typed else { return }
            if let fallback { copy(fallback.value, label: fallback.label) }
            if outcome == .failed { returnToForeground() }
        }
    }
}
