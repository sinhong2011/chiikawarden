import Foundation
import VaultwardenAPI

/// How to reach servers — trusted CAs, extra headers, device id — shared by the app and the AutoFill
/// extension through the App Group, so a passkey saved from Safari goes through the same proxy/CA setup.
enum Connection {
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: AccountStore.appGroup) ?? .standard

    /// PEM/DER certificates (public). Falls back to the app's own defaults from before they were shared.
    static var trustedCAs: [Data] {
        get { defaults.array(forKey: "trustedCAs") as? [Data] ?? UserDefaults.standard.array(forKey: "trustedCAs") as? [Data] ?? [] }
        set { defaults.set(newValue, forKey: "trustedCAs") }
    }

    static var deviceIdentifier: String {
        if let id = defaults.string(forKey: "deviceIdentifier") ?? UserDefaults.standard.string(forKey: "deviceIdentifier") {
            defaults.set(id, forKey: "deviceIdentifier")
            return id
        }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: "deviceIdentifier")
        return id
    }

    static func makeSession() -> URLSession {
        let cas = trustedCAs
        return cas.isEmpty ? URLSession.shared : ServerTrust(certificates: cas).makeSession()
    }

    /// A client for `environment` with the user's extra headers and trusted CAs applied.
    static func makeClient(_ environment: ServerEnvironment) -> VaultClient {
        VaultClient(environment: environment, deviceIdentifier: deviceIdentifier,
                    extraHeaders: HeaderStore.dictionary, session: makeSession())
    }
}

/// An extra HTTP header sent with every request, e.g. a Cloudflare Access service token.
struct CustomHeader: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var value: String
}

/// Stores custom headers as one Keychain item, since values are often credentials.
enum HeaderStore {
    private static let service = "io.github.sinhong2011.chiikawarden.headers"

    static func load() -> [CustomHeader] {
        Keychain.read(service: service).flatMap { try? JSONDecoder().decode([CustomHeader].self, from: $0) } ?? []
    }

    static func save(_ headers: [CustomHeader]) {
        let clean = headers.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        if !clean.isEmpty, let data = try? JSONEncoder().encode(clean) { Keychain.write(data, service: service) } else { Keychain.delete(service: service) }
    }

    static var dictionary: [String: String] {
        Dictionary(load().map { ($0.name.trimmingCharacters(in: .whitespaces), $0.value) }, uniquingKeysWith: { _, b in b })
    }
}
