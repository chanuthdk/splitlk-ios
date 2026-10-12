import Foundation
import UserNotifications

/// Schedules local reminders. Local rather than remote push, so the feature
/// needs no server and works fully in the Simulator.
@Observable
final class NotificationService {

    private let center = UNUserNotificationCenter.current()
    private let reminderPrefix = "settle-reminder-"

    var isAuthorized = false

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    /// Reminds the user about an unsettled balance after a delay.
    /// Scheduling per group means clearing one group's debt cancels only that reminder.
    func scheduleSettleReminder(groupID: UUID,
                                groupName: String,
                                amount: Decimal,
                                isOwedToMe: Bool,
                                afterDays days: Int) async {
        guard isAuthorized, days > 0 else { return }

        cancelSettleReminder(groupID: groupID)

        let content = UNMutableNotificationContent()
        content.title = groupName
        content.body = isOwedToMe
            ? "You're still owed \(Money.format(amount)) in this group."
            : "You still owe \(Money.format(amount)) in this group."
        content.sound = .default

        let interval = TimeInterval(days * 24 * 60 * 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 60), repeats: false)

        let request = UNNotificationRequest(
            identifier: reminderPrefix + groupID.uuidString,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    func cancelSettleReminder(groupID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: [reminderPrefix + groupID.uuidString]
        )
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    /// For the demo: fires in 10 seconds so the behaviour can be shown on camera.
    func scheduleDemoReminder(groupName: String) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = groupName
        content.body = "You're still owed Rs 2,450 in this group."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: reminderPrefix + "demo",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        )
        try? await center.add(request)
    }
}
