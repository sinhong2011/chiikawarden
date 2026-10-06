import Foundation

/// Sites that share sign-ins — the server's equivalent domains (yours, plus Bitwarden's global list unless you turned
/// a group off): a login saved for google.com also fills on youtube.com.
struct EquivalentDomains: Sendable {
    /// Each group's domains, lowercased.
    let groups: [Set<String>]

    static let none = EquivalentDomains(groups: [])

    init(groups: [Set<String>]) { self.groups = groups }

    /// From a sync payload (`domains`: `equivalentDomains` and `globalEquivalentDomains`, excluded ones skipped).
    init(syncData: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: syncData) as? [String: Any] else { self.init(groups: []); return }
        func value(_ dict: [String: Any], _ key: String) -> Any? { dict[key] ?? dict[key.prefix(1).uppercased() + key.dropFirst()] }
        guard let domains = value(root, "domains") as? [String: Any] else { self.init(groups: []); return }
        var groups: [Set<String>] = []
        for group in value(domains, "equivalentDomains") as? [[String]] ?? [] {
            groups.append(Set(group.map { $0.lowercased() }))
        }
        for global in value(domains, "globalEquivalentDomains") as? [[String: Any]] ?? [] {
            guard (value(global, "excluded") as? Bool) != true, let list = value(global, "domains") as? [String] else { continue }
            groups.append(Set(list.map { $0.lowercased() }))
        }
        self.init(groups: groups.filter { $0.count > 1 })
    }

    /// `host` itself or a subdomain of `domain`.
    static func within(_ host: String, _ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

    /// Every domain that shares sign-ins with `host` (including the one it falls under).
    func related(to host: String) -> Set<String> {
        let host = host.lowercased()
        return groups.filter { $0.contains { Self.within(host, $0) } }.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

    /// Whether a login saved for `itemHost` belongs on `site`: the same site or a subdomain either way, or two
    /// domains in one group.
    func matches(itemHost: String, site: String) -> Bool {
        let a = itemHost.lowercased(), b = site.lowercased()
        if Self.within(a, b) || Self.within(b, a) { return true }
        return groups.contains { group in group.contains { Self.within(a, $0) } && group.contains { Self.within(b, $0) } }
    }
}
