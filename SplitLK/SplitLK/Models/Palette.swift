import SwiftUI
import UIKit

/// The app's colour tokens, in one place.
///
/// Everything is defined as a light/dark pair and resolved by
/// `UIColor(dynamicProvider:)`, so a single token is correct in both
/// appearances. Views referred to raw hex strings before this existed, which
/// meant a hard-coded indigo stayed indigo on a dark background and the six
/// category colours were only ever checked in light mode.
///
/// The direction is "receipt": thermal-paper surfaces, near-black ink, and one
/// stamp blue for anything the user can act on. Green and red are reserved for
/// balance direction and are never used decoratively, because in this app they
/// are the difference between being owed and owing.
enum Palette {

    // MARK: - Surfaces

    /// The window behind grouped content.
    static let paper = dynamic(light: "EFEEE9", dark: "121211")
    /// Rows, cards and anything sitting on `paper`.
    static let card = dynamic(light: "FBFAF7", dark: "1C1C1A")
    /// Dividers. Drawn dashed in lists of money, like a receipt's tear line.
    static let rule = dynamic(light: "C9C7BE", dark: "3A3A36")

    // MARK: - Ink

    static let ink = dynamic(light: "17171A", dark: "EDEBE4")
    static let inkSoft = dynamic(light: "767672", dark: "9A9A93")

    // MARK: - Action

    /// The one colour that means "you can act on this". Mirrored into the
    /// asset catalogue's AccentColor so UIKit-backed controls match.
    static let stamp = dynamic(light: "1F5FD0", dark: "5B8EF0")

    // MARK: - Balance direction
    //
    // Reserved. Lightened in dark mode rather than reused, so the contrast
    // against a near-black surface stays readable.

    static let owed = dynamic(light: "0F6F4C", dark: "3FA87C")
    static let owing = dynamic(light: "B23A2C", dark: "D96A5C")

    // MARK: - Helpers

    private static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
