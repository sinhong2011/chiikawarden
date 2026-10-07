import AppKit
import CryptoKit
import Foundation
import Observation

/// Paid, but never locked — Fork's model. Every feature works without a license and there's no time limit; an
/// unregistered official build only asks, now and then at launch, whether you'd like to buy one.
///
/// Licenses are paid for through Lemon Squeezy (cards, Alipay, WeChat Pay, PayPal…), but the app never talks to
/// it or to any other license server: a license key is a small signed note — `<payload>.<signature>`, both
/// base64url, the payload JSON `{"n": name, "e": email, "o": order, "d": "yyyy-MM-dd"}` — and it's checked here,
/// offline, against the Ed25519 public key in Info.plist (`TWLicensePublicKey`). Keys are signed with
/// `make license` (scripts/license.swift); the private key never enters the repo.
///
/// An honour system: the source is GPL and anyone may build it without the reminder, which is fine. A build without
/// a store link or public key (forks) never reminds, and Debug builds never do either.
@MainActor @Observable
final class License {
    struct Registration: Codable, Equatable {
        var name: String
        var email: String
        var order: String
        var date: String

        enum CodingKeys: String, CodingKey { case name = "n", email = "e", order = "o", date = "d" }
    }

    enum Problem: LocalizedError {
        case invalid
        var errorDescription: String? { String(localized: "This license key isn't valid. Paste the whole key from your receipt.") }
    }

    /// Where "Buy License" goes; nil in builds without a store.
    let storeURL: URL?
    private let publicKey: Curve25519.Signing.PublicKey?
    private(set) var registration: Registration?
    /// The stored key, for showing its last characters.
    private(set) var key: String?

    var isConfigured: Bool { storeURL != nil && publicKey != nil }
    var isRegistered: Bool { registration != nil }

    private static let service = "io.github.sinhong2011.triwarden.license"
    private static let firstLaunchKey = "licenseFirstLaunch"
    private static let lastReminderKey = "licenseLastReminder"
    /// No reminder in the first week, then at most one a week.
    private static let grace: TimeInterval = 7 * 86_400
    private static let interval: TimeInterval = 7 * 86_400

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        storeURL = (info["TWStoreURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        publicKey = (info["TWLicensePublicKey"] as? String).flatMap { Data(base64Encoded: $0) }
            .flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
        if let stored = Keychain.read(service: Self.service).flatMap({ String(data: $0, encoding: .utf8) }),
           let registration = verify(stored) {
            self.key = stored
            self.registration = registration
        }
        if UserDefaults.standard.object(forKey: Self.firstLaunchKey) == nil {
            UserDefaults.standard.set(Date.now, forKey: Self.firstLaunchKey)
        }
    }

    /// Whether to show the reminder now (and, if so, note that it was shown).
    func takeReminder(now: Date = .now) -> Bool {
        #if DEBUG
        return false
        #else
        guard isConfigured, !isRegistered else { return false }
        let defaults = UserDefaults.standard
        let first = defaults.object(forKey: Self.firstLaunchKey) as? Date ?? now
        guard now.timeIntervalSince(first) >= Self.grace else { return false }
        if let last = defaults.object(forKey: Self.lastReminderKey) as? Date, now.timeIntervalSince(last) < Self.interval {
            return false
        }
        defaults.set(now, forKey: Self.lastReminderKey)
        return true
        #endif
    }

    func buy() {
        if let storeURL { NSWorkspace.shared.open(storeURL) }
    }

    /// Checks the key's signature (offline) and remembers it in the Keychain.
    func register(_ rawKey: String) throws {
        let key = rawKey.filter { !$0.isWhitespace }
        guard let registration = verify(key) else { throw Problem.invalid }
        Keychain.write(Data(key.utf8), service: Self.service)
        self.key = key
        self.registration = registration
    }

    /// Forgets the key on this Mac.
    func remove() {
        Keychain.delete(service: Self.service)
        key = nil
        registration = nil
    }

    private func verify(_ key: String) -> Registration? {
        let parts = key.split(separator: ".")
        guard let publicKey, parts.count == 2,
              let payload = Data(base64URL: parts[0]), let signature = Data(base64URL: parts[1]),
              publicKey.isValidSignature(signature, for: payload) else { return nil }
        return try? JSONDecoder().decode(Registration.self, from: payload)
    }
}

private extension Data {
    init?(base64URL text: Substring) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
