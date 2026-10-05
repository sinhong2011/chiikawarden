import Foundation

/// Listens on the server's SignalR notifications hub (MessagePack protocol) and calls `onChange`
/// whenever the vault changes elsewhere. We don't decode payloads: any non-ping message means "re-sync".
public actor LiveSync {
    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private let onChange: @Sendable () -> Void

    /// SignalR record separator, ends the JSON handshake.
    private static let recordSeparator = "\u{1e}"
    /// MessagePack Ping frame: length 2, fixarray(1) [6].
    static let pingFrame = Data([0x02, 0x91, 0x06])

    public init(environment: ServerEnvironment, accessToken: String, session: URLSession = .shared,
                onChange: @escaping @Sendable () -> Void) {
        var c = URLComponents(url: environment.notificationsURL, resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        c.queryItems = [URLQueryItem(name: "access_token", value: accessToken)]
        url = c.url!
        self.session = session
        self.onChange = onChange
    }

    public func start() async throws {
        do {
            try await connect(using: session)
        } catch {
            // Some HTTP proxies break WebSocket upgrades (notably plain ws:// on a LAN). Retry once direct.
            let direct = URLSessionConfiguration.ephemeral
            direct.connectionProxyDictionary = [:]
            try await connect(using: URLSession(configuration: direct, delegate: session.delegate, delegateQueue: nil))
        }
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await self?.sendPing()
            }
        }
        Task { await receiveLoop() }
    }

    private func connect(using session: URLSession) async throws {
        task?.cancel(with: .goingAway, reason: nil)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        try await task.send(.string(#"{"protocol":"messagepack","version":1}"# + Self.recordSeparator))
        _ = try await task.receive() // handshake ack "{}\u{1e}"
    }

    public func stop() {
        pingTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func sendPing() async {
        try? await task?.send(.data(Self.pingFrame))
    }

    private func receiveLoop() async {
        while let task {
            guard let message = try? await task.receive() else { return }
            if case .data(let data) = message, Self.containsChange(data) { onChange() }
        }
    }

    /// Splits varint-length-prefixed MessagePack frames; true if any frame isn't a Ping.
    static func containsChange(_ data: Data) -> Bool {
        var bytes = Array(data)[...]
        while !bytes.isEmpty {
            var length = 0, shift = 0
            while let b = bytes.first {
                bytes = bytes.dropFirst()
                length |= Int(b & 0x7f) << shift
                shift += 7
                if b & 0x80 == 0 { break }
            }
            guard length > 0, bytes.count >= length else { return false }
            let frame = bytes.prefix(length)
            bytes = bytes.dropFirst(length)
            if Array(frame) != [0x91, 0x06] { return true }
        }
        return false
    }
}

extension ServerEnvironment {
    public var notificationsURL: URL {
        switch self {
        case .bitwardenUS: URL(string: "https://notifications.bitwarden.com/hub")!
        case .bitwardenEU: URL(string: "https://notifications.bitwarden.eu/hub")!
        case .selfHosted(let base): base.appendingSlash.appending(path: "notifications/hub")
        }
    }
}
