import SwiftUI

/// A dashed horizontal rule, drawn like the perforation on a printed bill.
///
/// Used where one block of figures gives way to another — items to totals,
/// the net balance to the two halves it is made of. A plain hairline would do
/// the same job; this one says what kind of document the user is looking at.
struct TearLine: View {
    var body: some View {
        Rectangle()
            .fill(Palette.rule)
            .frame(height: 1)
            .mask(alignment: .leading) {
                // Dashes drawn as a stroked line rather than repeated shapes,
                // so the pattern stays even at any width.
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0.5))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    // The mask only reads alpha, but the stroke is given an
                    // explicit opaque colour rather than inheriting whatever
                    // foreground style happens to be in scope.
                    .foregroundStyle(.black)
                }
            }
            .accessibilityHidden(true)
    }
}

extension Font {
    /// Money is always set with tabular figures, so digits keep their column
    /// as a balance changes and a list of amounts lines up on the decimal
    /// the way a printed receipt does.
    static func money(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
        .system(style, weight: weight).monospacedDigit()
    }

    static func money(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}
