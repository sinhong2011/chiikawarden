import Foundation
import Security
import SwiftUI

/// UserDefaults keys for settings. Secrets (header values) live in the Keychain instead.
enum Pref {
    static let appearance = "appearance"           // "system" | "light" | "dark"
    static let autoLockMinutes = "autoLockMinutes" // 0 = never
    static let lockOnSleep = "lockOnSleep"
    static let lockAnimations = "lockAnimations"   // the vault door's moving lock screen and its open/close sequences
    static let clipboardSeconds = "clipboardSeconds" // 0 = never clear
    static let showIcons = "showIcons"
    static let sshAgent = "sshAgent"                 // serve SSH key items over the agent socket
    static let sshApprovalSeconds = "sshApprovalSeconds" // 0 = ask for every signature
    static let cli = "cli"                               // answer the `cw` command
    static let cliApprovalSeconds = "cliApprovalSeconds"
    static let browser = "browser"                       // answer the Safari/Chrome extension
    static let checkUpdates = "checkUpdates"             // opt-in: look at GitHub's latest release daily
    static let codeAfterPassword = "codeAfterPassword"   // after a password is pasted, the clipboard holds its code
    static let hideFromCapture = "hideFromCapture"       // windows stay out of screen sharing, recordings and screenshots
    static let timeoutAction = "timeoutAction"           // after inactivity: "lock" or "logOut" (accounts may override)

    static func register() {
        UserDefaults.standard.register(defaults: [
            appearance: "system", autoLockMinutes: 15, lockOnSleep: true, lockAnimations: true, clipboardSeconds: 30,
            codeAfterPassword: true, hideFromCapture: false, timeoutAction: "lock", // opt-in: some screen tools and recordings need the window
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
