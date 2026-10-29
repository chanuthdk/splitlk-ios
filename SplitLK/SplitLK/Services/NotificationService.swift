import Foundation
import UserNotifications

/// One scheduled reminder, as the user would see it listed.
struct PendingReminder: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date?
}

/// Schedules local reminders about balances that have not been settled.
///
/// Local rather than remote push: no server, no certificates, and it runs
/// fully in the Simulator, which is where this app is demonstrated.
///
/// The class is also the notification centre's delegate. That is not optional
/// decoration — without a delegate, iOS suppresses a notification that fires
/// while the app is in the foreground, so a reminder triggered during a demo
/// would do nothing at all.
@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    /// Categories and actions are registered once and referenced by these ids.
    static let settleCategory = "SETTLE_REMINDER"
    static let settleAction = "SETTLE_NOW"
    static let snoozeAction = "SNOOZE_1D"

    /// Called when the user taps a reminder, or its "Settle up" action, so the
    /// app can open the group the reminder was about.
    var onOpenGroup: ((UUID) -> Void)?

    var isAuthorized = false

    private var center: UNUserNotificationCenter { .current() }
    private let reminderPrefix = "settle-reminder-"

    override init() {
        super.init()
        center.delegate = self

        let settle = UNNotificationAction(identifier: Self.settleAction,
                                          title: "Settle up",
                                          options: [.foreground])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction,
                                          title: "Remind me tomorrow",
                                          options: [])
        let category = UNNotificationCategory(identifier: Self.settleCategory,
                                              actions: [settle, snooze],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
    }

    // MARK: - Authorisation

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

    // MARK: - Scheduling

    /// Reminds the user about an unsettled balance after a delay.
    /// Scheduled per group, so clearing one group's debt cancels only its own
    /// reminder and leaves the others alone.
    func scheduleSettleReminder(groupID: UUID,
                                groupName: String,
                                amount: Decimal,
                                isOwedToMe: Bool,
                                afterDays days: Int) async {
        guard isAuthorized, days > 0 else { return }
        let interval = TimeInterval(days * 24 * 60 * 60)
        await schedule(groupID: groupID,
                       groupName: groupName,
                       amount: amount,
                       isOwedToMe: isOwedToMe,
                       after: max(interval, 60))
    }

    private func schedule(groupID: UUID,
                          groupName: String,
                          amount: Decimal,
                          isOwedToMe: Bool,
                          after interval: TimeInterval) async {
        cancelSettleReminder(groupID: groupID)

        let content = UNMutableNotificationContent()
        content.title = groupName
        content.body = isOwedToMe
            ? "You're still owed \(Money.format(amount)) in this group."
            : "You still owe \(Money.format(amount)) in this group."
        content.sound = .default
        content.categoryIdentifier = Self.settleCategory
        content.interruptionLevel = .active
        // Carried so the tap handler knows which group to open, and so the
        // snooze action can rebuild the same reminder a day later.
        content.userInfo = [
            "groupID": groupID.uuidString,
            "groupName": groupName,
            "amount": "\(amount)",
            "isOwedToMe": isOwedToMe
        ]

        let request = UNNotificationRequest(
            identifier: reminderPrefix + groupID.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
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

    /// What is currently queued, so Settings can show the user that the
    /// feature did something rather than asking them to take it on trust.
    func pendingReminders() async -> [PendingReminder] {
        let requests = await center.pendingNotificationRequests()
        return requests
            .filter { $0.content.categoryIdentifier == Self.settleCategory }
            .map { request in
                PendingReminder(
                    id: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    fireDate: (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                )
            }
            .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
    }

    /// For the demo: fires in ten seconds so the banner, its actions and the
    /// tap-through can all be shown on camera without waiting a day.
    func scheduleDemoReminder(groupID: UUID?, groupName: String) async {
        guard isAuthorized else { return }
        await schedule(groupID: groupID ?? UUID(),
                       groupName: groupName,
                       amount: 2450,
                       isOwedToMe: true,
                       after: 10)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Without this, a reminder that fires while the app is open is silently
    /// dropped by iOS and the user sees nothing.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let groupID = (info["groupID"] as? String).flatMap(UUID.init(uuidString:))

        switch response.actionIdentifier {
        case Self.snoozeAction:
            guard let groupID,
                  let name = info["groupName"] as? String,
                  let raw = info["amount"] as? String,
                  let amount = Decimal(string: raw) else { return }
            let isOwedToMe = info["isOwedToMe"] as? Bool ?? true
            await schedule(groupID: groupID,
                           groupName: name,
                           amount: amount,
                           isOwedToMe: isOwedToMe,
                           after: 24 * 60 * 60)

        default:
            // Covers both the "Settle up" action and a plain tap on the banner.
            guard let groupID else { return }
            await MainActor.run { self.onOpenGroup?(groupID) }
        }
    }
}
