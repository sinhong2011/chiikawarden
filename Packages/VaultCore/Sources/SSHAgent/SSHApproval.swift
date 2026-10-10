import Foundation

public struct ProcessNode: Equatable, Sendable {
    public var pid: Int32
    public var parent: Int32
    public var path: String?
    public init(pid: Int32, parent: Int32, path: String?) {
        self.pid = pid
        self.parent = parent
        self.path = path
    }
}

public struct SSHRequester: Equatable, Sendable {
    public var displayName: String
    public var via: String
    public var peerPath: String?
    public var appPath: String?
    public var appPID: Int32?
    public var trustKey: String
    public init(displayName: String, via: String, peerPath: String?, appPath: String?, appPID: Int32?, trustKey: String) {
        self.displayName = displayName
        self.via = via
        self.peerPath = peerPath
        self.appPath = appPath
        self.appPID = appPID
        self.trustKey = trustKey
    }
}

public enum SSHRequesterResolver {
    /// The first `.app` bundle walking from `pid` toward its parents, at most eight steps.
    /// Pid 0 and 1 stop the walk. A display name is the bundle's file name, or the peer name.
    public static func resolve(pid: Int32, peerPath: String?, peerName: String, lookup: (Int32) -> ProcessNode?) -> SSHRequester {
        var current = pid
        var appPath: String?
        var appPID: Int32?
        for _ in 0..<8 where current > 1 {
            guard let node = lookup(current) else { break }
            if let path = node.path, let bundle = bundlePath(in: path) {
                appPath = bundle
                appPID = node.pid
                break
            }
            current = node.parent
        }
        let trustKey = appPath.map { "path:\($0)" } ?? peerPath.map { "path:\($0)" } ?? "name:\(peerName)"
        let displayName = appPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? peerName
        return SSHRequester(displayName: displayName, via: peerName, peerPath: peerPath, appPath: appPath, appPID: appPID, trustKey: trustKey)
    }

    static func bundlePath(in path: String) -> String? {
        var built = ""
        for component in path.split(separator: "/") where !component.isEmpty {
            built += "/\(component)"
            if component.hasSuffix(".app") { return built }
        }
        return nil
    }
}
