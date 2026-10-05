import Foundation
import Testing
@testable import SSHAgent

@Suite(.serialized) struct SSHAgentTests {
    static let dir = FileManager.default.temporaryDirectory.appending(path: "chiikawa-agent-\(getpid())")
    static let keyTypes: [(String, [String])] = [
        ("ed25519", ["-t", "ed25519"]), ("ecdsa256", ["-t", "ecdsa", "-b", "256"]), ("ecdsa384", ["-t", "ecdsa", "-b", "384"]),
        ("ecdsa521", ["-t", "ecdsa", "-b", "521"]), ("rsa2048", ["-t", "rsa", "-b", "2048"]), ("rsa3072", ["-t", "rsa", "-b", "3072"]),
    ]

    @discardableResult
    static func run(_ tool: String, _ args: [String], env: [String: String] = [:], stdin: Data? = nil) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/\(tool)")
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        let out = Pipe(), input = Pipe()
        p.standardOutput = out; p.standardError = out; p.standardInput = input
        try p.run()
        if let stdin { input.fileHandleForWriting.write(stdin) }
        try input.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func makeKey(_ name: String, _ args: [String]) throws -> (pem: String, pub: String, path: URL) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appending(path: name)
        try? FileManager.default.removeItem(at: path)
        try? FileManager.default.removeItem(at: path.appendingPathExtension("pub"))
        try run("ssh-keygen", args + ["-q", "-N", "", "-C", "\(name)@test", "-f", path.path])
        return (try String(contentsOf: path, encoding: .utf8),
                try String(contentsOf: path.appendingPathExtension("pub"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), path)
    }

    @Test func bigMod() {
        #expect(BigMod.mod(Data([0x01, 0x00, 0x00]), Data([0x07])) == Data([0x02])) // 65536 mod 7
        #expect(BigMod.mod(Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF]), Data([0x01, 0x00, 0x01])) == Data([0xff]))
        #expect(BigMod.minusOne(Data([0x01, 0x00])) == Data([0xFF]))
    }

    @Test func parsesEveryKeyType() throws {
        for (name, args) in Self.keyTypes {
            let k = try Self.makeKey(name, args)
            let key = try SSHPrivateKey(pem: k.pem)
            #expect(key.authorizedKey == k.pub, "\(name)")
        }
    }

    @Test func rejectsEncryptedKeys() throws {
        let k = try Self.makeKey("enc", ["-t", "ed25519"])
        try Self.run("ssh-keygen", ["-p", "-q", "-N", "secret", "-P", "", "-f", k.path.path])
        let pem = try String(contentsOf: k.path, encoding: .utf8)
        #expect(throws: SSHPrivateKey.Failure.encrypted) { try SSHPrivateKey(pem: pem) }
    }

    @Test func servesSshAddAndSignsForSshKeygen() async throws {
        let keys = try Self.keyTypes.map { name, args in
            let k = try Self.makeKey(name, args)
            return (SSHAgentServer.Identity(id: name, name: "\(name)@test", key: try SSHPrivateKey(pem: k.pem)), k)
        }
        let socket = Self.dir.appending(path: "agent.sock")
        let approvals = Approvals()
        let agent = SSHAgentServer(socketURL: socket, identities: { keys.map(\.0) },
                                   approve: { identity, peer in await approvals.record(identity.id, peer.processName) })
        try agent.start()
        defer { agent.stop() }
        let env = ["SSH_AUTH_SOCK": socket.path]

        let (status, listed) = try Self.run("ssh-add", ["-L"], env: env)
        #expect(status == 0)
        for (_, k) in keys { #expect(listed.contains(k.pub)) }

        let message = Data("tree 1234\nauthor usagi\n\nsigned commit\n".utf8)
        for (identity, k) in keys {
            let (signStatus, sigOutput) = try Self.run("ssh-keygen", ["-Y", "sign", "-n", "git", "-f", k.path.path + ".pub", "-q"],
                                                       env: env, stdin: message)
            #expect(signStatus == 0, "\(identity.id): \(sigOutput)")
            let sigFile = Self.dir.appending(path: "\(identity.id).sig")
            try Data(sigOutput.utf8).write(to: sigFile)
            let signers = Self.dir.appending(path: "allowed_signers")
            try Data("usagi@test \(k.pub)\n".utf8).write(to: signers)
            let (verify, verifyOut) = try Self.run("ssh-keygen", ["-Y", "verify", "-n", "git", "-I", "usagi@test", "-f", signers.path,
                                                                  "-s", sigFile.path], stdin: message)
            #expect(verify == 0, "\(identity.id): \(verifyOut)")
        }
        let asked = await approvals.asked
        #expect(asked.count == keys.count && asked.allSatisfy { $0.1 == "ssh-keygen" })

        // Denied → the client gets a failure.
        await approvals.deny()
        let (denied, _) = try Self.run("ssh-keygen", ["-Y", "sign", "-n", "git", "-f", keys[0].1.path.path + ".pub", "-q"],
                                       env: env, stdin: message)
        #expect(denied != 0)
    }
}

actor Approvals {
    private(set) var asked: [(String, String)] = []
    private var allow = true
    func record(_ id: String, _ process: String) -> Bool { asked.append((id, process)); return allow }
    func deny() { allow = false }
}
