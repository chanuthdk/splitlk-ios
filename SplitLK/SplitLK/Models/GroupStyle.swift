import SwiftUI

/// The colour and symbol choices offered when a group is created.
///
/// Kept as plain strings rather than an enum because they are persisted, and
/// an enum would break the moment a future version renamed a case or a group
/// arrived from a device running a different build.
enum GroupStyle {

    static let defaultColorHex = "4F46E5"
    static let defaultIconName = "person.3.fill"

    /// Deliberately distinct hues rather than shades of one colour, so a row
    /// is identifiable at a glance and in greyscale the icons still differ.
    static let colors = ["4F46E5", "0891B2", "16A34A", "D97706",
                         "DC2626", "DB2777", "7C3AED", "475569"]

    /// Occasions people actually split money for. Each one has to read at
    /// 16pt inside a 40pt circle, which rules out the more detailed symbols.
    static let icons = ["person.3.fill", "airplane", "house.fill",
                        "fork.knife", "beach.umbrella.fill", "car.fill",
                        "cart.fill", "music.note", "gift.fill",
                        "graduationcap.fill", "sportscourt.fill", "tent.fill"]

    /// A stable colour for a group that has none, picked from its name so the
    /// same group looks the same on every device without storing anything.
    static func fallbackColorHex(for name: String) -> String {
        guard !name.isEmpty else { return defaultColorHex }
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        return colors[hash % colors.count]
    }
}

extension SpendingCategory {
    /// Each category gets its own colour so a bill list is scannable without
    /// reading it. The hues match the group palette, so the two sets of
    /// colours look like they belong to the same app.
    var color: Color {
        switch self {
        case .food:          return Color(hex: "D97706")
        case .drinks:        return Color(hex: "0891B2")
        case .transport:     return Color(hex: "16A34A")
        case .groceries:     return Color(hex: "7C3AED")
        case .accommodation: return Color(hex: "DB2777")
        case .other:         return Color(hex: "475569")
        }
    }
}
