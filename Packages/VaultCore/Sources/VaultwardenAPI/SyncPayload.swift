import Foundation

/// Edits a cached sync payload in place of downloading it again: one item at a time.
public enum SyncPayload {
    /// The payload with these items replaced (or added), and those mapped to nil removed. Everything else is kept
    /// byte-for-byte as the server sent it. Nil when the payload can't be read.
    public static func replacingCiphers(in payload: Data, with changes: [String: Data?]) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return nil }
        let key = root.keys.first { $0.lowercased() == "ciphers" } ?? "ciphers"
        var ciphers = root[key] as? [[String: Any]] ?? []
        var remaining = changes
        ciphers = ciphers.compactMap { cipher in
            guard let id = id(of: cipher), let change = remaining.removeValue(forKey: id) else { return cipher }
            return change.flatMap(object)
        }
        for (_, change) in remaining.sorted(by: { $0.key < $1.key }) {
            if let added = change.flatMap(object) { ciphers.append(added) }
        }
        root[key] = ciphers
        return try? JSONSerialization.data(withJSONObject: root)
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func id(of cipher: [String: Any]) -> String? {
        (cipher["id"] ?? cipher["Id"]) as? String
    }
}
