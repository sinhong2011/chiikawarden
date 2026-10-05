import Foundation
import Security
import SwiftUI

/// UserDefaults keys for settings. Secrets (header values) live in the Keychain instead.
enum Pref {
    static let appearance = "appearance"           // "system" | "light" | "dark"
    static let autoLockMinutes = "autoLockMinutes" // 0 = never
    static let lockOnSleep = "lockOnSleep"
    static let clipboardSeconds = "clipboardSeconds" // 0 = never clear
    static let trustedCAs = "trustedCAs"           // [Data], PEM/DER certificates (public)

    static func register() {
        UserDefaults.standard.register(defaults: [
            appearance: "system", autoLockMinutes: 15, lockOnSleep: true, clipboardSeconds: 30,
        ])
    }

    static var colorScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: appearance) {
        case "light": .light
        case "dark": .dark
        default: nil
        }
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
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return [] }
        return (try? JSONDecoder().decode([CustomHeader].self, from: data)) ?? []
    }

    static func save(_ headers: [CustomHeader]) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(base as CFDictionary)
        let clean = headers.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !clean.isEmpty, let data = try? JSONEncoder().encode(clean) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static var dictionary: [String: String] {
        Dictionary(load().map { ($0.name.trimmingCharacters(in: .whitespaces), $0.value) }, uniquingKeysWith: { _, b in b })
    }
}
