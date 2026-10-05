import Foundation
import Security
import SwiftUI

/// UserDefaults keys for settings. Secrets (header values) live in the Keychain instead.
enum Pref {
    static let appearance = "appearance"           // "system" | "light" | "dark"
    static let autoLockMinutes = "autoLockMinutes" // 0 = never
    static let lockOnSleep = "lockOnSleep"
    static let clipboardSeconds = "clipboardSeconds" // 0 = never clear
    static let showIcons = "showIcons"
    static let sshAgent = "sshAgent"                 // serve SSH key items over the agent socket
    static let sshApprovalSeconds = "sshApprovalSeconds" // 0 = ask for every signature
    static let cli = "cli"                               // answer the `cw` command
    static let cliApprovalSeconds = "cliApprovalSeconds"

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
