import Foundation

// Endpoints beyond the vault basics: organizations, bulk edits, account security, devices, two-step login,
// sign-in requests, emergency access, equivalent domains and event logs. Bodies and answers are plain JSON
// (already encrypted where they hold secrets); callers decode what they need.

extension VaultClient {
    /// An authorized call to the API with an optional JSON body; returns the answer's bytes.
    @discardableResult
    public func call(_ method: String, _ path: String, json body: Any? = nil) async throws(APIError) -> Data {
        var r = try request(environment.apiURL, path)
        r.httpMethod = method
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do { r.httpBody = try JSONSerialization.data(withJSONObject: body) } catch { throw .http(status: -1, message: "encode") }
        }
        return try await sendRaw(authorized(r))
    }

    /// The same, decoded as a JSON object (camelCase keys, whatever case the server used).
    public func callJSON(_ method: String, _ path: String, json body: Any? = nil) async throws(APIError) -> [String: Any] {
        let data = try await call(method, path, json: body)
        guard !data.isEmpty else { return [:] }
        return (CipherEditor.normalize(try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }

    // MARK: Organizations and bulk edits

    /// Moves a personal item into an organization (`cipher` re-encrypted with the organization key, see
    /// `CipherEditor.sharedCipher`), into the given collections.
    public func shareCipher(id: String, cipher: [String: Any], collectionIds: [String]) async throws(APIError) {
        try await call("PUT", "ciphers/\(id)/share", json: ["cipher": cipher, "collectionIds": collectionIds])
    }

    /// Sets which collections an organization item is in.
    public func setCollections(cipherId: String, collectionIds: [String]) async throws(APIError) {
        try await call("PUT", "ciphers/\(cipherId)/collections_v2", json: ["collectionIds": collectionIds])
    }

    /// Moves personal items into a folder (nil: out of any folder).
    public func moveCiphers(ids: [String], folderId: String?) async throws(APIError) {
        try await call("PUT", "ciphers/move", json: ["ids": ids, "folderId": folderId ?? NSNull()] as [String: Any])
    }

    public func trashCiphers(ids: [String]) async throws(APIError) { try await call("PUT", "ciphers/delete", json: ["ids": ids]) }
    public func restoreCiphers(ids: [String]) async throws(APIError) { try await call("PUT", "ciphers/restore", json: ["ids": ids]) }
    public func deleteCiphers(ids: [String]) async throws(APIError) { try await call("DELETE", "ciphers", json: ["ids": ids]) }
    public func archiveCiphers(ids: [String]) async throws(APIError) { try await call("PUT", "ciphers/archive", json: ["ids": ids]) }

    public func leaveOrganization(id: String) async throws(APIError) { try await call("POST", "organizations/\(id)/leave") }
}
