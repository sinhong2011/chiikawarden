import Darwin
import Foundation

/// An ssh-agent (draft-miller-ssh-agent) on a Unix socket. It lists keys and signs, and asks `approve`
/// before every signature. It never adds, removes or exports keys.
public final class SSHAgentServer: @unchecked Sendable {
    public struct Identity: Sendable {
        public let id: String
        public let name: String
        public let key: SSHPrivateKey
        public init(id: String, name: String, key: SSHPrivateKey) { self.id = id; self.name = name; self.key = key }
    }

    /// The process on the other end of the socket.
    public struct Peer: Sendable {
        public let pid: pid_t
        public let processName: String
    }

    public enum Failure: Error { case pathTooLong, socket(Int32) }

    public let socketURL: URL
    private let identities: @Sendable () async -> [Identity]
    private let approve: @Sendable (Identity, Peer) async -> Bool
    private let lock = NSLock()
    private var listener: Int32 = -1

    public init(socketURL: URL,
                identities: @escaping @Sendable () async -> [Identity],
                approve: @escaping @Sendable (Identity, Peer) async -> Bool) {
        self.socketURL = socketURL
        self.identities = identities
        self.approve = approve
    }

    public var isRunning: Bool { lock.withLock { listener >= 0 } }

    public func start() throws {
        guard !isRunning else { return }
        let path = socketURL.path
        var addr = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw Failure.pathTooLong }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket(errno) }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: path.utf8)
            buf[path.utf8.count] = 0
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) } }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let err = errno
            close(fd)
            throw Failure.socket(err)
        }
        lock.withLock { listener = fd }
        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "ssh-agent accept"
        thread.start()
    }

    public func stop() {
        let fd = lock.withLock { () -> Int32 in defer { listener = -1 }; return listener }
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR)
        close(fd)
        unlink(socketURL.path)
    }

    deinit { stop() }

    // MARK: Connections

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return // listener closed
            }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let thread = Thread { [weak self] in
                self?.serve(client)
                close(client)
            }
            thread.name = "ssh-agent connection"
            thread.start()
        }
    }

    private func serve(_ fd: Int32) {
        let peer = Self.peer(of: fd)
        while let request = Self.readMessage(fd) {
            let reply = blocking { await self.handle(request, peer: peer) }
            guard Self.writeMessage(fd, reply) else { return }
        }
    }

    /// Runs async work from a connection thread (never a cooperative-pool thread).
    private func blocking<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: T?
        Task.detached { result = await work(); done.signal() }
        done.wait()
        return result!
    }

    enum Message {
        static let failure: UInt8 = 5
        static let requestIdentities: UInt8 = 11
        static let identitiesAnswer: UInt8 = 12
        static let signRequest: UInt8 = 13
        static let signResponse: UInt8 = 14
    }

    func handle(_ request: Data, peer: Peer) async -> Data {
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

    // MARK: Framing

    private static func readExactly(_ fd: Int32, _ n: Int) -> Data? {
        var out = Data(count: n)
        var got = 0
        while got < n {
            let k = out.withUnsafeMutableBytes { read(fd, $0.baseAddress! + got, n - got) }
            if k < 0, errno == EINTR { continue }
            guard k > 0 else { return nil }
            got += k
        }
        return out
    }

    static func readMessage(_ fd: Int32) -> Data? {
        guard let header = readExactly(fd, 4) else { return nil }
        let length = header.reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length <= 256 * 1024 else { return nil }
        return readExactly(fd, length)
    }

    static func writeMessage(_ fd: Int32, _ body: Data) -> Bool {
        var w = SSHWriter()
        w.string(body)
        let frame = w.data
        var sent = 0
        while sent < frame.count {
            let k = frame.withUnsafeBytes { write(fd, $0.baseAddress! + sent, frame.count - sent) }
            if k < 0, errno == EINTR { continue }
            guard k > 0 else { return false }
            sent += k
        }
        return true
    }

    static func peer(of fd: Int32) -> Peer {
        var pid: pid_t = 0
        var len = socklen_t(MemoryLayout<pid_t>.size)
        getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len)
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let name = proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0
            ? URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
            : "pid \(pid)"
        return Peer(pid: pid, processName: name)
    }
}
