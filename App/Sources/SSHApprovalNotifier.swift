import Foundation
import SSHAgent
import UserNotifications

/// A banner that only brings the approval card forward. It never approves a signature.
enum SSHApprovalNotifier {
    private static let category = "ssh-approval"

    static func arm(_ prompt: SSHPrompt) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(prompt.displayName) wants to sign")
            content.body = prompt.keyName
            content.categoryIdentifier = category
            content.userInfo = ["id": prompt.id.uuidString]
            let request = UNNotificationRequest(identifier: prompt.id.uuidString, content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
            center.add(request)
        }
    }

    static func cancel(_ id: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }
}

extension Notification.Name {
    static let sshApprovalReveal = Notification.Name("sshApprovalReveal")
}

/// Not main-actor isolated, so the system can deliver the tap without crossing a Sendable boundary into `AppDelegate`.
final class SSHNotificationBridge: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            NotificationCenter.default.post(name: .sshApprovalReveal, object: nil)
        }
    }
}
