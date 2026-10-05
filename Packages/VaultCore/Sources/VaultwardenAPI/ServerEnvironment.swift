import Foundation

/// Per-service URLs for a self-hosted server ("Custom environment"). Any empty one is derived like the
/// official clients do: base + suffix, else web vault + suffix.
public struct CustomURLs: Sendable, Hashable, Codable {
    public var base: URL?
    public var webVault: URL?
    public var api: URL?
    public var identity: URL?
    public var icons: URL?
    public var notifications: URL?

    public init(base: URL? = nil, webVault: URL? = nil, api: URL? = nil, identity: URL? = nil,
                icons: URL? = nil, notifications: URL? = nil) {
        self.base = base; self.webVault = webVault; self.api = api
        self.identity = identity; self.icons = icons; self.notifications = notifications
    }

    /// Explicit URL, else base + suffix, else web vault + suffix.
    func resolve(_ explicit: URL?, suffix: String) -> URL? {
        if let explicit { return explicit.appendingSlash }
        if let root = base ?? webVault { return root.appendingSlash.appending(path: suffix + "/") }
        return nil
    }

    public var isUsable: Bool { resolve(api, suffix: "api") != nil && resolve(identity, suffix: "identity") != nil }
}

/// Where an account lives: the official Bitwarden cloud or a self-hosted (Vaultwarden) server.
public enum ServerEnvironment: Sendable, Hashable, Codable {
    case bitwardenUS
    case bitwardenEU
    case selfHosted(URL)
    /// Self-hosted with some services on their own URLs.
    case custom(CustomURLs)

    public var apiURL: URL {
        switch self {
        case .bitwardenUS: URL(string: "https://api.bitwarden.com/")!
        case .bitwardenEU: URL(string: "https://api.bitwarden.eu/")!
        case .selfHosted(let base): base.appendingSlash.appending(path: "api/")
        case .custom(let urls): urls.resolve(urls.api, suffix: "api") ?? URL(string: "https://invalid.invalid/")!
        }
    }

    public var identityURL: URL {
        switch self {
        case .bitwardenUS: URL(string: "https://identity.bitwarden.com/")!
        case .bitwardenEU: URL(string: "https://identity.bitwarden.eu/")!
        case .selfHosted(let base): base.appendingSlash.appending(path: "identity/")
        case .custom(let urls): urls.resolve(urls.identity, suffix: "identity") ?? URL(string: "https://invalid.invalid/")!
        }
    }

    /// Icon service root: `<iconsURL>/<domain>/icon.png`.
    public var iconsURL: URL? {
        switch self {
        case .bitwardenUS, .bitwardenEU: URL(string: "https://icons.bitwarden.net/")
        case .selfHosted(let base): base.appendingSlash.appending(path: "icons/")
        case .custom(let urls): urls.resolve(urls.icons, suffix: "icons")
        }
    }

    public var isOfficialCloud: Bool {
        switch self {
        case .bitwardenUS, .bitwardenEU: true
        case .selfHosted, .custom: false
        }
    }

    /// Short label for UI, e.g. "bitwarden.com" or "vault.home.arpa".
    public var displayHost: String {
        switch self {
        case .bitwardenUS: "bitwarden.com"
        case .bitwardenEU: "bitwarden.eu"
        case .selfHosted(let base): base.host() ?? base.absoluteString
        case .custom(let urls): (urls.webVault ?? urls.base ?? urls.api)?.host() ?? "custom"
        }
    }
}
