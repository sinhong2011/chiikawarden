import AppKit
import Darwin
import Foundation
import SSHAgent

enum SSHProcess {
    static func node(_ pid: pid_t) -> ProcessNode? {
        var info = proc_bsdshortinfo()
        let size = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info)))
        guard size == Int32(MemoryLayout.size(ofValue: info)) else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let n = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return 0 }
            return base.withMemoryRebound(to: CChar.self, capacity: ptr.count) { proc_pidpath(pid, $0, UInt32(ptr.count)) }
        }
        let path: String? = n > 0 ? String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self) : nil
        return ProcessNode(pid: Int32(bitPattern: info.pbsi_pid), parent: Int32(bitPattern: info.pbsi_ppid), path: path)
    }

    /// Bundle id and Team ID for a signed process. Unsigned or unreadable processes contribute nothing.
    static func signature(of pid: pid_t) -> (bundleID: String?, teamID: String?) {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return (nil, nil) }
        return (dict[kSecCodeInfoIdentifier as String] as? String, dict[kSecCodeInfoTeamIdentifier as String] as? String)
    }

    static func requester(for peer: SSHAgentServer.Peer) -> SSHRequester {
        var who = SSHRequesterResolver.resolve(pid: peer.pid, peerPath: peer.path, peerName: peer.processName, lookup: node)
        if let appPID = who.appPID {
            let signing = signature(of: appPID)
            who.trustKey = SSHTrustKey.make(bundleID: signing.bundleID, teamID: signing.teamID,
                                            appPath: who.appPath, peerPath: who.peerPath, peerName: who.via)
            if let name = NSRunningApplication(processIdentifier: appPID)?.localizedName, !name.isEmpty {
                who.displayName = name
            }
        }
        return who
    }
}
