import Testing
import Foundation
@testable import SplitLK

/// These exercise the keyword fallback, which is what runs when the trained
/// model is not bundled. The model's own accuracy is measured in Create ML
/// against a held-out split rather than here.
struct CategoryClassifierTests {

    init() {
        CategoryClassifier.forgetCorrections()
    }

    @Test("Local dishes are recognised as food")
    func localDishes() {
        #expect(CategoryClassifier.category(for: "Chicken Kottu") == .food)
        #expect(CategoryClassifier.category(for: "Watalappan") == .food)
        #expect(CategoryClassifier.category(for: "String Hoppers") == .food)
    }

    @Test("Drinks are told apart from food")
    func drinks() {
        #expect(CategoryClassifier.category(for: "Lime Juice") == .drinks)
        #expect(CategoryClassifier.category(for: "Lion Lager") == .drinks)
        #expect(CategoryClassifier.category(for: "Iced Coffee") == .drinks)
    }

    @Test("Transport lines are recognised")
    func transport() {
        #expect(CategoryClassifier.category(for: "Tuk-tuk to Unawatuna") == .transport)
        #expect(CategoryClassifier.category(for: "Petrol") == .transport)
        #expect(CategoryClassifier.category(for: "Train Ticket") == .transport)
    }

    @Test("A service charge is not read as food")
    func serviceChargeIsNotFood() {
        // "service charge" is longer than any food keyword it contains,
        // so the longest-match rule keeps it out of the food total.
        #expect(CategoryClassifier.category(for: "Service Charge 10%") == .other)
    }

    @Test("Longer keywords win over shorter ones inside them")
    func longestMatchWins() {
        #expect(CategoryClassifier.category(for: "Ice Cream") == .food)
    }

    @Test("An unrecognised item falls back to other rather than guessing")
    func unknownFallsBack() {
        #expect(CategoryClassifier.category(for: "Zxqv Wgth") == .other)
    }

    @Test("An empty name is not categorised")
    func emptyName() {
        #expect(CategoryClassifier.category(for: "   ") == .other)
    }

    @Test("A correction is remembered for next time")
    func correctionsAreRemembered() {
        let item = "Mystery Platter"
        #expect(CategoryClassifier.category(for: item) == .other)

        CategoryClassifier.remember(.food, for: item)
        #expect(CategoryClassifier.category(for: item) == .food)

        // Matching ignores case and extra spacing, so the same line read
        // slightly differently by OCR still picks up the correction.
        #expect(CategoryClassifier.category(for: "  mystery   platter ") == .food)

        CategoryClassifier.forgetCorrections()
        #expect(CategoryClassifier.category(for: item) == .other)
    }

    @Test("A correction overrides what the classifier would have said")
    func correctionBeatsKeyword() {
        CategoryClassifier.remember(.groceries, for: "Bread Roll")
        #expect(CategoryClassifier.category(for: "Bread Roll") == .groceries)
        CategoryClassifier.forgetCorrections()
    }
}
