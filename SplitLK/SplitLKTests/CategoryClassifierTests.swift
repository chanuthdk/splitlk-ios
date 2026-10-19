import Testing
import Foundation
@testable import SplitLK

/// The keyword pass is tested directly rather than through `category(for:)`,
/// because that entry point uses the trained model when one is bundled. These
/// assertions are about the fallback's own behaviour, which has to hold
/// whether or not the model shipped.
struct KeywordFallbackTests {

    @Test("Local dishes are recognised as food")
    func localDishes() {
        #expect(CategoryClassifier.keywordCategory(for: "chicken kottu") == .food)
        #expect(CategoryClassifier.keywordCategory(for: "watalappan") == .food)
        #expect(CategoryClassifier.keywordCategory(for: "string hoppers") == .food)
    }

    @Test("Drinks are told apart from food")
    func drinks() {
        #expect(CategoryClassifier.keywordCategory(for: "lime juice") == .drinks)
        #expect(CategoryClassifier.keywordCategory(for: "lion lager") == .drinks)
        #expect(CategoryClassifier.keywordCategory(for: "iced coffee") == .drinks)
    }

    @Test("Transport lines are recognised")
    func transport() {
        #expect(CategoryClassifier.keywordCategory(for: "tuk-tuk to unawatuna") == .transport)
        #expect(CategoryClassifier.keywordCategory(for: "petrol") == .transport)
        #expect(CategoryClassifier.keywordCategory(for: "train ticket") == .transport)
    }

    @Test("A service charge is not read as food")
    func serviceChargeIsNotFood() {
        // "service charge" is longer than any food keyword inside the line,
        // and the longest match wins, so it stays out of the food total.
        #expect(CategoryClassifier.keywordCategory(for: "service charge 10%") == .other)
    }

    @Test("Longer keywords win over shorter ones inside them")
    func longestMatchWins() {
        #expect(CategoryClassifier.keywordCategory(for: "ice cream") == .food)
    }

    @Test("An unrecognised item falls back to other rather than guessing")
    func unknownFallsBack() {
        #expect(CategoryClassifier.keywordCategory(for: "zxqv wgth") == .other)
    }
}

struct CategoryCorrectionTests {

    init() {
        CategoryClassifier.forgetCorrections()
    }

    @Test("An empty name is not categorised")
    func emptyName() {
        #expect(CategoryClassifier.category(for: "   ") == .other)
    }

    @Test("A correction overrides whatever the classifier would have said")
    func correctionWins() {
        let item = "Mystery Platter"
        CategoryClassifier.remember(.groceries, for: item)
        #expect(CategoryClassifier.category(for: item) == .groceries)
        CategoryClassifier.forgetCorrections()
    }

    @Test("A correction survives a differently formatted version of the name")
    func correctionIsCaseAndSpaceInsensitive() {
        CategoryClassifier.remember(.accommodation, for: "Beach Cabana")
        // OCR rarely returns the same spacing or case twice.
        #expect(CategoryClassifier.category(for: "  beach   CABANA ") == .accommodation)
        CategoryClassifier.forgetCorrections()
    }

    @Test("Forgetting corrections restores the normal behaviour")
    func forgettingWorks() {
        CategoryClassifier.remember(.transport, for: "Chicken Kottu")
        #expect(CategoryClassifier.category(for: "Chicken Kottu") == .transport)

        CategoryClassifier.forgetCorrections()
        #expect(CategoryClassifier.category(for: "Chicken Kottu") == .food)
    }

    @Test("Corrections are kept per item, not applied globally")
    func correctionsAreScopedToOneItem() {
        CategoryClassifier.remember(.groceries, for: "Bread")
        #expect(CategoryClassifier.category(for: "Bread") == .groceries)
        // A different item is unaffected.
        #expect(CategoryClassifier.category(for: "Lime Juice") == .drinks)
        CategoryClassifier.forgetCorrections()
    }
}
