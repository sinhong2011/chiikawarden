import Foundation

/// An ssh-agent (draft-miller-ssh-agent) on a Unix socket. It lists keys and signs, and asks `approve`
/// before every signature. It never adds, removes or exports keys.
public final class SSHAgentServer: Sendable {
    public struct Identity: Sendable {
        public let id: String
        public let name: String
        public let key: SSHPrivateKey
        public init(id: String, name: String, key: SSHPrivateKey) { self.id = id; self.name = name; self.key = key }
    }

    public typealias Peer = FramedSocketServer.Peer
    public typealias Failure = FramedSocketServer.Failure

    private let server: FramedSocketServer
    public var socketURL: URL { server.socketURL }
    public var isRunning: Bool { server.isRunning }

    public init(socketURL: URL,
                identities: @escaping @Sendable () async -> [Identity],
                approve: @escaping @Sendable (Identity, Peer) async -> Bool) {
        server = FramedSocketServer(socketURL: socketURL) { request, peer in
            await Self.handle(request, peer: peer, identities: identities, approve: approve)
        }
    }

    public func start() throws { try server.start() }
    public func stop() { server.stop() }

    enum Message {
        static let failure: UInt8 = 5
        static let requestIdentities: UInt8 = 11
        static let identitiesAnswer: UInt8 = 12
        static let signRequest: UInt8 = 13
        static let signResponse: UInt8 = 14
    }

    static func handle(_ request: Data, peer: Peer,
                       identities: @Sendable () async -> [Identity],
                       approve: @Sendable (Identity, Peer) async -> Bool) async -> Data {
        var r = SSHReader(request)
        guard let type = try? r.uint8() else { return Data([Message.failure]) }
        switch type {
        case Message.requestIdentities:
            let ids = await identities()
            var w = SSHWriter()
            w.uint8(Message.identitiesAnswer)
            w.uint32(UInt32(ids.count))
            for id in ids { w.string(id.key.publicBlob); w.string(id.name) }
            return w.data
        case Message.signRequest:
            guard let blob = try? r.string(), let data = try? r.string() else { return Data([Message.failure]) }
            let flags = SSHPrivateKey.SignFlags(rawValue: (try? r.uint32()) ?? 0)
            guard let identity = await identities().first(where: { $0.key.publicBlob == blob }),
                  await approve(identity, peer),
                  let signature = try? identity.key.sign(data, flags: flags) else { return Data([Message.failure]) }
            var w = SSHWriter()
            w.uint8(Message.signResponse)
            w.string(signature)
            return w.data
        default:
            // Adding/removing keys, locking, extensions (session-bind): not offered.
            return Data([Message.failure])
        }
    }
}
