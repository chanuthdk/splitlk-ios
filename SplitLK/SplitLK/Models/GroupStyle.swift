import SwiftUI

/// The colour and symbol choices offered when a group is created.
///
/// Kept as plain strings rather than an enum because they are persisted, and
/// an enum would break the moment a future version renamed a case or a group
/// arrived from a device running a different build.
enum GroupStyle {

    static let defaultColorHex = "17171A"
    static let defaultIconName = "person.3.fill"

    /// Muted and roughly equal in weight, so no group shouts over the others
    /// and none of them competes with the green and red that carry balance
    /// direction. Distinct in hue rather than in brightness, so the rows stay
    /// tellable apart in greyscale too.
    static let colors = ["17171A", "3C6B78", "44683C", "8A6A32",
                         "8E4654", "5E4E73", "1F5FD0", "5E5E58"]

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
    /// reading it, drawn from the same muted family as the group palette.
    ///
    /// Deliberately held back: on a receipt the amounts are what matter, and
    /// six saturated circles down the left edge would outshout them. These
    /// read as printed ink rather than as highlighting.
    var color: Color {
        switch self {
        case .food:          return Color(hex: "8A6A32")   // turmeric
        case .drinks:        return Color(hex: "3C6B78")   // slate blue
        case .transport:     return Color(hex: "44683C")   // palm
        case .groceries:     return Color(hex: "5E4E73")   // aubergine
        case .accommodation: return Color(hex: "8E4654")   // madder
        case .other:         return Color(hex: "5E5E58")   // stone
        }
    }
}
