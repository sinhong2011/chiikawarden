import CryptoKit
import Foundation

/// Have I Been Pwned "range" API with k-anonymity: only the first 5 hex chars of each password's SHA-1
/// leave the device, and responses are padded so their size doesn't hint at the result.
public enum PwnedPasswords {
    static let endpoint = URL(string: "https://api.pwnedpasswords.com/range/")!

    /// Returns how many times each password appears in known breaches (0 = not found).
    public static func check(_ passwords: Set<String>, session: URLSession = .shared) async throws -> [String: Int] {
        var byPrefix: [String: [(password: String, suffix: String)]] = [:]
        for password in passwords {
            let hex = Insecure.SHA1.hash(data: Data(password.utf8)).map { String(format: "%02X", $0) }.joined()
            byPrefix[String(hex.prefix(5)), default: []].append((password, String(hex.dropFirst(5))))
        }
        var result: [String: Int] = [:]
        try await withThrowingTaskGroup(of: [String: Int].self) { group in
            for (prefix, entries) in byPrefix {
                group.addTask {
                    var request = URLRequest(url: endpoint.appending(path: prefix))
                    request.setValue("true", forHTTPHeaderField: "Add-Padding")
                    request.setValue("Chiikawarden", forHTTPHeaderField: "User-Agent")
                    let (data, response) = try await session.data(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    let counts = parse(String(decoding: data, as: UTF8.self))
                    return Dictionary(entries.map { ($0.password, counts[$0.suffix] ?? 0) }, uniquingKeysWith: { a, _ in a })
                }
            }
            for try await partial in group { result.merge(partial) { a, _ in a } }
        }
        return result
    }

    /// "SUFFIX:COUNT" lines; padding entries have count 0.
    static func parse(_ body: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for line in body.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":")
            if parts.count == 2, let n = Int(parts[1].trimmingCharacters(in: .whitespaces)), n > 0 {
                out[String(parts[0]).uppercased()] = n
            }
        }
        return out
    }
}
