import Foundation

/// JSON messages between the `cw` command and the app (one frame each way per request).
public struct CLIRequest: Codable, Sendable, Equatable {
    public enum Command: String, Codable, Sendable { case status, list, get, code, generate, lock }
    public var command: Command
    public var query: String?
    /// For `get`: password (default), username, uri, notes, totp, or a custom field name.
    public var field: String?
    public var length: Int?

    public init(command: Command, query: String? = nil, field: String? = nil, length: Int? = nil) {
        self.command = command; self.query = query; self.field = field; self.length = length
    }
}

public struct CLIResponse: Codable, Sendable, Equatable {
    public struct Row: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var detail: String
        public init(id: String, name: String, detail: String) { self.id = id; self.name = name; self.detail = detail }
    }

    public var ok: Bool
    public var value: String?
    public var rows: [Row]?
    public var error: String?

    public static func success(_ value: String) -> CLIResponse { CLIResponse(ok: true, value: value) }
    public static func list(_ rows: [Row]) -> CLIResponse { CLIResponse(ok: true, rows: rows) }
    public static func failure(_ message: String) -> CLIResponse { CLIResponse(ok: false, error: message) }
}

public enum CLISocket {
    /// File name inside the App Group container.
    public static let name = "cli.sock"
}
