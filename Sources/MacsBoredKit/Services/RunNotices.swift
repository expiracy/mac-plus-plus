#if canImport(AppKit)
import AppKit
import UserNotifications
import MacsBoredCore

/// The notification an action shows when it runs, if it asks for one: its name, and what it did.
/// macOS asks once whether mac++ may show them. Outside an app bundle (`swift run`) there's no
/// notification center to ask, so nothing shows.
@MainActor
enum RunNotices {
    /// Asks macOS to let mac++ show notifications, if it hasn't been asked yet: when an action is set
    /// to show one.
    static func ask() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(_ trigger: Trigger) {
        guard let center else { return }
        let notice = trigger.notice
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.threadIdentifier = "actions"
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private static var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = Banner.shared }
        return center
    }

    /// Shows the banner even while mac++ is the app in front (its dropdown open, say).
    private final class Banner: NSObject, UNUserNotificationCenterDelegate {
        static let shared = Banner()

        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list])
        }
    }
}
#endif
