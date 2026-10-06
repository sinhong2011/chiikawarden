import Foundation

/// Listens on the server's SignalR notifications hub (MessagePack protocol) and calls `onChange` whenever the vault
/// changes elsewhere: with the item's id when one item was created, edited or deleted, else "something changed".
public actor LiveSync {
    /// What a notification says changed.
    public enum Change: Sendable, Equatable {
        /// One item was created, updated or deleted: fetching just it is enough.
        case cipher(String)
        /// Anything else (folders, organizations, settings, many items, or a message that couldn't be read): sync.
        case other
    }

    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private let onChange: @Sendable ([Change]) -> Void

    /// SignalR record separator, ends the JSON handshake.
    private static let recordSeparator = "\u{1e}"
    /// MessagePack Ping frame: length 2, fixarray(1) [6].
    static let pingFrame = Data([0x02, 0x91, 0x06])

    public init(environment: ServerEnvironment, accessToken: String, session: URLSession = .shared,
                onChange: @escaping @Sendable ([Change]) -> Void) {
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
            if case .data(let data) = message {
                let changes = Self.changes(in: data)
                if !changes.isEmpty { onChange(changes) }
            }
        }
    }

    /// True if any frame isn't a Ping.
    static func containsChange(_ data: Data) -> Bool { !changes(in: data).isEmpty }

    /// Bitwarden's push types for one item: cipher updated, created, login deleted, cipher deleted.
    static let cipherTypes: Set<Int> = [0, 1, 2, 9]

    /// Splits varint-length-prefixed MessagePack frames and reads each: pings say nothing; an invocation about one
    /// item names it; anything else, or anything unreadable, is `.other` (sync everything, to be safe).
    static func changes(in data: Data) -> [Change] {
        var bytes = Array(data)[...]
        var out: [Change] = []
        while !bytes.isEmpty {
            var length = 0, shift = 0
            while let b = bytes.first {
                bytes = bytes.dropFirst()
                length |= Int(b & 0x7f) << shift
                shift += 7
                if b & 0x80 == 0 { break }
            }
            guard length > 0, bytes.count >= length else { return out.isEmpty ? [] : out }
            let frame = Array(bytes.prefix(length))
            bytes = bytes.dropFirst(length)
            if frame == [0x91, 0x06] { continue } // Ping
            out.append(change(in: frame))
        }
        return out
    }

    /// `[1, headers, invocationId, "ReceiveMessage", [{ContextId, Type, Payload: {Id, …}}]]`
    private static func change(in frame: [UInt8]) -> Change {
        var reader = MessagePackReader(frame)
        guard case .array(let message)? = try? reader.read(), message.count >= 5, message[0].int == 1,
              case .array(let arguments) = message[4], case .map(let notification)? = arguments.first,
              let type = notification["Type"]?.int, cipherTypes.contains(type),
              case .map(let payload)? = notification["Payload"], let id = payload["Id"]?.string
        else { return .other }
        return .cipher(id)
    }
}

extension ServerEnvironment {
    public var notificationsURL: URL {
        switch self {
        case .bitwardenUS: URL(string: "https://notifications.bitwarden.com/hub")!
        case .bitwardenEU: URL(string: "https://notifications.bitwarden.eu/hub")!
        case .selfHosted(let base): base.appendingSlash.appending(path: "notifications/hub")
        case .custom(let urls):
            (urls.resolve(urls.notifications, suffix: "notifications") ?? URL(string: "https://invalid.invalid/")!).appending(path: "hub")
        }
    }
}

/// Just enough MessagePack to read SignalR notifications.
struct MessagePackReader {
    indirect enum Value: Equatable {
        case null, bool(Bool), int(Int), double(Double), string(String), binary([UInt8]), array([Value]), map([String: Value]), ext

        var int: Int? { if case .int(let v) = self { v } else { nil } }
        var string: String? { if case .string(let v) = self { v } else { nil } }
    }

    struct Truncated: Error {}

    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    private mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, index + n <= bytes.count else { throw Truncated() }
        defer { index += n }
        return bytes[index..<index + n]
    }

    private mutating func uint(_ n: Int) throws -> UInt64 {
        try take(n).reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func read() throws -> Value {
        let b = try take(1).first!
        switch b {
        case 0x00...0x7f: return .int(Int(b))
        case 0x80...0x8f: return try map(Int(b & 0x0f))
        case 0x90...0x9f: return try array(Int(b & 0x0f))
        case 0xa0...0xbf: return try string(Int(b & 0x1f))
        case 0xc0: return .null
        case 0xc2: return .bool(false)
        case 0xc3: return .bool(true)
        case 0xc4, 0xc5, 0xc6: return .binary(Array(try take(Int(try uint(1 << Int(b - 0xc4))))))
        case 0xc7, 0xc8, 0xc9: _ = try take(Int(try uint(1 << Int(b - 0xc7))) + 1); return .ext
        case 0xca: return .double(Double(Float(bitPattern: UInt32(try uint(4)))))
        case 0xcb: return .double(Double(bitPattern: try uint(8)))
        case 0xcc, 0xcd, 0xce, 0xcf: return .int(Int(truncatingIfNeeded: try uint(1 << Int(b - 0xcc))))
        case 0xd0: return .int(Int(Int8(truncatingIfNeeded: try uint(1))))
        case 0xd1: return .int(Int(Int16(truncatingIfNeeded: try uint(2))))
        case 0xd2: return .int(Int(Int32(truncatingIfNeeded: try uint(4))))
        case 0xd3: return .int(Int(Int64(bitPattern: try uint(8))))
        case 0xd4, 0xd5, 0xd6, 0xd7, 0xd8: _ = try take((1 << Int(b - 0xd4)) + 1); return .ext
        case 0xd9, 0xda, 0xdb: return try string(Int(try uint(1 << Int(b - 0xd9))))
        case 0xdc, 0xdd: return try array(Int(try uint(b == 0xdc ? 2 : 4)))
        case 0xde, 0xdf: return try map(Int(try uint(b == 0xde ? 2 : 4)))
        case 0xe0...0xff: return .int(Int(Int8(bitPattern: b)))
        default: throw Truncated() // 0xc1 is never used
        }
    }

    private mutating func string(_ n: Int) throws -> Value { .string(String(decoding: try take(n), as: UTF8.self)) }

    private mutating func array(_ n: Int) throws -> Value {
        var out: [Value] = []
        for _ in 0..<n { out.append(try read()) }
        return .array(out)
    }

    private mutating func map(_ n: Int) throws -> Value {
        var out: [String: Value] = [:]
        for _ in 0..<n {
            let key = try read()
            let value = try read()
            if let key = key.string { out[key] = value }
        }
        return .map(out)
    }
}
