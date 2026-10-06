import Foundation
import Testing
@testable import VaultwardenAPI

/// Reading which item a push notification is about, and editing the cached sync payload one item at a time.
@Suite struct LiveChangeTests {
    /// A tiny MessagePack writer for building frames like the notifications hub sends.
    private indirect enum M {
        case null, int(Int), str(String), arr([M]), map([(String, M)]), timestamp

        var bytes: [UInt8] {
            switch self {
            case .null: [0xc0]
            case .int(let v): v >= 0 && v < 128 ? [UInt8(v)] : [0xd2] + withUnsafeBytes(of: Int32(v).bigEndian, Array.init)
            case .str(let s): [0xa0 | UInt8(s.utf8.count)] + Array(s.utf8)
            case .arr(let a): [0x90 | UInt8(a.count)] + a.flatMap(\.bytes)
            case .map(let m): [0x80 | UInt8(m.count)] + m.flatMap { M.str($0.0).bytes + $0.1.bytes }
            case .timestamp: [0xd7, 0xff] + [UInt8](repeating: 1, count: 8) // ext -1, 8 bytes
            }
        }
    }

    private func frame(_ m: M) -> Data {
        let body = m.bytes
        precondition(body.count < 128)
        return Data([UInt8(body.count)] + body)
    }

    private func notification(type: Int, id: String = "c1") -> Data {
        frame(.arr([.int(1), .map([]), .null, .str("ReceiveMessage"), .arr([
            .map([("ContextId", .str("dev")), ("Type", .int(type)),
                  ("Payload", .map([("Id", .str(id)), ("UserId", .str("u")), ("RevisionDate", .timestamp)]))]),
        ])]))
    }

    @Test func oneItemChanges() {
        #expect(LiveSync.changes(in: notification(type: 0, id: "abc")) == [.cipher("abc")]) // updated
        #expect(LiveSync.changes(in: notification(type: 1)) == [.cipher("c1")])             // created
        #expect(LiveSync.changes(in: notification(type: 2)) == [.cipher("c1")])             // login deleted
        #expect(LiveSync.changes(in: notification(type: 9)) == [.cipher("c1")])             // cipher deleted
    }

    @Test func everythingElseSyncs() {
        #expect(LiveSync.changes(in: notification(type: 5)) == [.other])  // whole vault
        #expect(LiveSync.changes(in: notification(type: 7)) == [.other])  // folder created
        #expect(LiveSync.changes(in: LiveSync.pingFrame + Data([0x03, 0x93, 0x01, 0x80])) == [.other]) // unreadable
        #expect(LiveSync.changes(in: LiveSync.pingFrame).isEmpty)
        #expect(LiveSync.changes(in: LiveSync.pingFrame + notification(type: 0, id: "x")) == [.cipher("x")])
    }

    @Test func payloadReplacesAddsAndRemoves() throws {
        let payload = Data(#"{"object":"sync","profile":{"id":"u"},"ciphers":[{"id":"a","name":"A"},{"id":"b","name":"B"}]}"#.utf8)
        let out = try #require(SyncPayload.replacingCiphers(in: payload, with: [
            "a": Data(#"{"id":"a","name":"A2","favorite":true}"#.utf8),
            "b": nil,
            "c": Data(#"{"id":"c","name":"C"}"#.utf8),
        ]))
        let root = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        let ciphers = try #require(root["ciphers"] as? [[String: Any]])
        #expect(ciphers.compactMap { $0["id"] as? String } == ["a", "c"])
        #expect(ciphers[0]["name"] as? String == "A2")
        #expect(ciphers[0]["favorite"] as? Bool == true)
        #expect((root["profile"] as? [String: Any])?["id"] as? String == "u")
    }

    @Test func payloadWithPascalCaseKeys() throws {
        let payload = Data(#"{"Ciphers":[{"Id":"a","Name":"A"}]}"#.utf8)
        let out = try #require(SyncPayload.replacingCiphers(in: payload, with: ["a": nil]))
        let root = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        #expect((root["Ciphers"] as? [Any])?.isEmpty == true)
    }
}
