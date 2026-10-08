import Foundation
import QuartzCore
import TriCrypto

/// Timing marks for `scripts/bench.sh`: with `TRIWARDEN_BENCH=1` in the environment, `mark` prints
/// `BENCH <name> <ms>` to stderr, the milliseconds counted from when the kernel started the process (so dyld, the
/// runtime and app init are inside the number). Off otherwise, and cheap: one environment lookup at launch.
enum Bench {
    static let on = ProcessInfo.processInfo.environment["TRIWARDEN_BENCH"] != nil

    /// When the kernel started this process.
    private static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return .now }
        let t = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000)
    }()

    nonisolated(unsafe) private static var marked: Set<String> = []
    nonisolated(unsafe) private static var started: [String: Date] = [:]

    /// Prints a mark; `once` marks (launch milestones) print only the first time.
    static func mark(_ name: String, once: Bool = true) {
        guard on, !once || marked.insert(name).inserted else { return }
        let ms = Date.now.timeIntervalSince(processStart) * 1000
        FileHandle.standardError.write(Data(String(format: "BENCH %@ %.1f\n", name, ms).utf8))
    }

    /// Prints a mark once the frame being built now is on screen (after Core Animation commits it).
    static func markAfterCommit(_ name: String) {
        guard on, !marked.contains(name) else { return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { mark(name) }
        CATransaction.commit()
    }

    /// Starts a span (an unlock); `end` prints how long it took as `BENCH <name> <ms>`.
    static func begin(_ name: String) {
        guard on else { return }
        started[name] = .now
    }

    static func end(_ name: String) {
        guard on, let start = started.removeValue(forKey: name) else { return }
        let ms = Date.now.timeIntervalSince(start) * 1000
        FileHandle.standardError.write(Data(String(format: "BENCH %@ %.1f\n", name, ms).utf8))
    }

    /// Ends the open-the-vault spans once the frame now being built is on screen.
    static func endAfterCommit(_ names: [String]) {
        guard on else { return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { names.forEach(end) }
        CATransaction.commit()
    }

    #if DEBUG
    /// `--bench-unlock`: times a master-password unlock offline — exactly the steps `AccountStore.unlock` takes (derive
    /// the master key with the account's KDF, stretch it, decrypt the user key) — for Bitwarden's default KDF
    /// settings, and exits. Prints `BENCH unlock-<kdf> <median ms>`.
    static func runUnlockIfRequested() {
        guard CommandLine.arguments.contains("--bench-unlock") else { return }
        let runs = 5
        let configs: [(String, KDFConfig)] = [
            ("pbkdf2-600k", .pbkdf2(iterations: 600_000)),
            ("argon2id-64m-3-4", .argon2id(iterations: 3, memoryMiB: 64, parallelism: 4)),
        ]
        let email = "alex@example.com"
        let password = "correct horse battery staple"
        for (name, kdf) in configs {
            do {
                var userKey = Data(count: 64)
                _ = userKey.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 64, $0.baseAddress!) }
                let stretched = try SymmetricKeyPair.stretched(masterKey: KDF.masterKey(password: password, email: email, config: kdf))
                let protected = try EncString.encrypt(userKey, with: stretched).description
                var times: [Double] = []
                for _ in 0..<runs {
                    let start = Date.now
                    let mk = try KDF.masterKey(password: password, email: email, config: kdf)
                    let key = try SymmetricKeyPair.stretched(masterKey: mk)
                    let raw = try EncString(protected).decrypt(with: key)
                    _ = try SymmetricKeyPair(combined: raw)
                    times.append(Date.now.timeIntervalSince(start) * 1000)
                }
                let median = times.sorted()[runs / 2]
                print(String(format: "BENCH unlock-%@ %.1f", name, median))
            } catch {
                print("BENCH unlock-\(name) failed: \(error)")
            }
        }
        exit(0)
    }
    #endif
}
