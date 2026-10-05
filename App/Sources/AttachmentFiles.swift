import Foundation

/// Decrypted attachment copies for Quick Look. They live in a private folder inside the sandbox
/// container, are readable only by this user, and are deleted when the preview closes, on lock and at launch.
enum AttachmentFiles {
    static let root = FileManager.default.temporaryDirectory.appending(path: "Attachments", directoryHint: .isDirectory)

    static func write(_ data: Data, named name: String) throws -> URL {
        let dir = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Keep the real name (Quick Look picks the viewer by extension) but never let it escape the folder.
        let safe = name.replacingOccurrences(of: "/", with: "∕").replacingOccurrences(of: ":", with: "∶")
        let url = dir.appending(path: safe.isEmpty || safe.hasPrefix(".") ? "attachment" + safe : safe)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    /// Removes one preview's folder.
    static func remove(_ url: URL) {
        let dir = url.deletingLastPathComponent()
        guard dir.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    static func wipe() { try? FileManager.default.removeItem(at: root) }
}
