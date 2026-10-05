import Foundation

/// Where an account lives: the official Bitwarden cloud or a self-hosted (Vaultwarden) server.
public enum ServerEnvironment: Sendable, Hashable, Codable {
    case bitwardenUS
    case bitwardenEU
    case selfHosted(URL)

    public var apiURL: URL {
        switch self {
        case .bitwardenUS: URL(string: "https://api.bitwarden.com/")!
        case .bitwardenEU: URL(string: "https://api.bitwarden.eu/")!
        case .selfHosted(let base): base.appendingSlash.appending(path: "api/")
        }
    }

    public var identityURL: URL {
        switch self {
        case .bitwardenUS: URL(string: "https://identity.bitwarden.com/")!
        case .bitwardenEU: URL(string: "https://identity.bitwarden.eu/")!
        case .selfHosted(let base): base.appendingSlash.appending(path: "identity/")
        }
    }

    public var isOfficialCloud: Bool {
        if case .selfHosted = self { false } else { true }
    }

    /// Short label for UI, e.g. "bitwarden.com" or "vault.home.arpa".
    public var displayHost: String {
        switch self {
        case .bitwardenUS: "bitwarden.com"
        case .bitwardenEU: "bitwarden.eu"
        case .selfHosted(let base): base.host() ?? base.absoluteString
        }
    }
}
