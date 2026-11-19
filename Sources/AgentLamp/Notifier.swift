import AgentLampCore
import AppKit
import UserNotifications

/// Posts one banner per session. A newer banner for the same session replaces the older one.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onClick: (Int32) -> Void = { _ in }

    /// UNUserNotificationCenter crashes outside an .app bundle, for example under `swift run`.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()

    func setUp() {
        center?.delegate = self
        center?.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func post(_ event: LampEvent) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        let record = event.record
        switch event.state {
        case .blocked:
            content.title = "\(record.displayName) is waiting for you"
            content.body = record.waitingFor.map { "Needs \($0) in \(record.cwd)" } ?? record.cwd
        default:
            content.title = "\(record.displayName) finished"
            content.body = "Your turn in \(record.cwd)"
        }
        content.userInfo = ["pid": Int(record.pid)]
        center.add(UNNotificationRequest(identifier: record.sessionId, content: content, trigger: nil))
    }

    /// Removes banners for sessions that no longer need the user.
    func clear(sessionIds: [String]) {
        guard !sessionIds.isEmpty else { return }
        center?.removeDeliveredNotifications(withIdentifiers: sessionIds)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let pid = response.notification.request.content.userInfo["pid"] as? Int
        if let pid {
            Task { @MainActor in self.onClick(Int32(pid)) }
        }
        completionHandler()
    }
}
