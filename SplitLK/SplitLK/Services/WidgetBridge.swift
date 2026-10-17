import Foundation
import WidgetKit

/// A small, precomputed summary of the user's balances, shared between the
/// app and its widget through an App Group container.
///
/// The widget deliberately does not open the Core Data store. A widget runs
/// under a tight memory budget and has to render almost immediately, and
/// recomputing every group's ledger there would be both slow and fragile.
/// The app already knows these numbers, so it writes them out whenever they
/// change and the widget just reads the file.
struct BalanceSnapshot: Codable {

    struct GroupSummary: Codable, Identifiable {
        var id: UUID
        var name: String
        /// Positive means the user is owed money in this group.
        var balance: Decimal
    }

    var owedToMe: Decimal
    var iOwe: Decimal
    var groups: [GroupSummary]
    var updatedAt: Date

    var net: Decimal { owedToMe - iOwe }

    var isSettled: Bool { owedToMe == 0 && iOwe == 0 }

    static let empty = BalanceSnapshot(owedToMe: 0, iOwe: 0, groups: [], updatedAt: .distantPast)

    /// Shown in the widget gallery and in previews, where no real data exists.
    static let placeholder = BalanceSnapshot(
        owedToMe: 4200,
        iOwe: 800,
        groups: [
            GroupSummary(id: UUID(), name: "Galle Trip", balance: 2450),
            GroupSummary(id: UUID(), name: "Colombo Flat", balance: -800),
            GroupSummary(id: UUID(), name: "Office Lunch", balance: 1750)
        ],
        updatedAt: Date()
    )
}

enum WidgetBridge {

    /// Must match the App Group added to both the app and the widget target.
    static let appGroupID = "group.com.chanuth.SplitLK"

    static let widgetKind = "SplitLKBalanceWidget"

    private static let filename = "balance-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(filename)
    }

    // MARK: - Reading

    /// Returns the last snapshot the app wrote, or an empty one. A missing
    /// file is normal: it just means the app has not run since install.
    static func read() -> BalanceSnapshot {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(BalanceSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    // MARK: - Writing

    static func write(_ snapshot: BalanceSnapshot) {
        guard let fileURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }

        try? data.write(to: fileURL, options: .atomic)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
