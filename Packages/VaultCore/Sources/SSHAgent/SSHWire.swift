import Foundation

/// SSH wire encoding (RFC 4251 §5): uint32, string, mpint.
struct SSHReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) { self.data = Data(data); offset = 0 }

    var isAtEnd: Bool { offset >= data.count }
    var remaining: Data { data[offset...] }

    enum Failure: Error { case truncated }

    mutating func uint8() throws -> UInt8 {
        guard offset < data.count else { throw Failure.truncated }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func uint32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw Failure.truncated }
        defer { offset += 4 }
        return data[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func bytes(_ n: Int) throws -> Data {
        guard n >= 0, offset + n <= data.count else { throw Failure.truncated }
        defer { offset += n }
        return Data(data[offset..<offset + n])
    }

    mutating func string() throws -> Data { try bytes(Int(uint32())) }
    mutating func text() throws -> String { String(decoding: try string(), as: UTF8.self) }

    /// mpint as unsigned big-endian magnitude (leading zero stripped).
    mutating func mpint() throws -> Data {
        var d = try string()
        while d.first == 0 { d.removeFirst() }
        return d
    }
}

struct SSHWriter {
    private(set) var data = Data()

    mutating func uint8(_ v: UInt8) { data.append(v) }
    mutating func uint32(_ v: UInt32) { data.append(contentsOf: [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]) }
    mutating func string(_ d: Data) { uint32(UInt32(d.count)); data.append(d) }
    mutating func string(_ s: String) { string(Data(s.utf8)) }

    /// Unsigned magnitude → mpint (prepends 0x00 when the high bit is set).
    mutating func mpint(_ magnitude: Data) {
        var m = magnitude.drop { $0 == 0 }
        if let first = m.first, first & 0x80 != 0 { m.insert(0, at: m.startIndex) }
        string(Data(m))
    }
}
