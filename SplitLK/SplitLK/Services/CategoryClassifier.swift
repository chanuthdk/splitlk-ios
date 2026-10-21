import Foundation
import NaturalLanguage
import CoreML

/// Works out which spending category a receipt line belongs to, on-device.
///
/// Three things are tried in order, cheapest and most certain first:
///   1. a correction the user has already made for this item name
///   2. a Create ML text classifier trained on local item names
///   3. keyword matching
///
/// The keyword pass exists so the feature degrades rather than disappears
/// when the model is missing, and so a brand new install still categorises
/// something sensible on its very first scan.
enum CategoryClassifier {

    /// Loaded by filename rather than by the class Create ML generates, so
    /// this file compiles whether or not the model has been added yet.
    private static let modelName = "ItemCategoryClassifier"

    private static let model: NLModel? = {
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: modelName, withExtension: "mlmodel") else {
            return nil
        }
        guard let compiled = try? MLModel(contentsOf: url),
              let nlModel = try? NLModel(mlModel: compiled) else {
            return nil
        }
        return nlModel
    }()

    /// True when the trained model is present. Shown in Settings so the
    /// behaviour is visible rather than silently different.
    static var isModelAvailable: Bool { model != nil }

    // MARK: - Classifying

    static func category(for itemName: String) -> SpendingCategory {
        let name = normalise(itemName)
        guard !name.isEmpty else { return .other }

        if let remembered = CorrectionStore.category(for: name) {
            return remembered
        }

        if let category = modelCategory(for: name) {
            return category
        }

        return keywordCategory(for: name)
    }

    /// The model's answer, but only when it is reasonably sure.
    ///
    /// A classifier always returns its best label, even for an item it has
    /// never seen anything like — so without a floor, a misread line becomes
    /// a confident wrong category rather than an honest "other". Below the
    /// threshold the keyword pass gets a say instead.
    private static let minimumConfidence = 0.45

    private static func modelCategory(for name: String) -> SpendingCategory? {
        guard let model else { return nil }

        let hypotheses = model.predictedLabelHypotheses(for: name, maximumCount: 1)
        guard let (label, confidence) = hypotheses.max(by: { $0.value < $1.value }),
              confidence >= minimumConfidence else {
            return nil
        }

        return SpendingCategory(rawValue: label)
    }

    /// Records a correction so the same item is categorised the user's way
    /// next time. Cheaper and more predictable than retraining, and it means
    /// a wrong guess only has to be fixed once.
    static func remember(_ category: SpendingCategory, for itemName: String) {
        CorrectionStore.save(category, for: normalise(itemName))
    }

    static func forgetCorrections() {
        CorrectionStore.clear()
    }

    // MARK: - Fallback

    private static let keywords: [(SpendingCategory, [String])] = [
        (.drinks, ["juice", "soda", "cola", "coke", "sprite", "water", "beer",
                   "lager", "arrack", "wine", "whisky", "vodka", "coffee",
                   "tea", "milkshake", "lassi", "thambili", "cocktail",
                   "mojito", "latte", "cappuccino", "espresso", "mocktail"]),
        (.transport, ["tuk", "taxi", "cab", "uber", "pickme", "bus", "train",
                      "fuel", "petrol", "diesel", "parking", "toll", "fare",
                      "rental", "hire", "flight", "ferry", "transfer",
                      "trishaw", "three wheeler"]),
        (.groceries, ["keells", "cargills", "arpico", "laugfs", "supermarket",
                      "grocery", "groceries", "rice 5kg", "milk powder",
                      "detergent", "shampoo", "soap", "toothpaste"]),
        (.accommodation, ["hotel", "room", "guest house", "guesthouse",
                          "villa", "hostel", "airbnb", "resort", "bungalow",
                          "cabana", "lodging", "stay", "homestay", "suite"]),
        (.food, ["kottu", "rice", "curry", "hopper", "roti", "biriyani",
                 "burger", "pizza", "sandwich", "noodles", "pasta", "salad",
                 "soup", "chicken", "fish", "prawn", "cutlet", "vadai",
                 "samosa", "cake", "pudding", "ice cream", "watalappan",
                 "fries", "wings", "buffet", "meal", "bun", "roll"]),
        // "ticket" is deliberately absent: a train ticket is transport and a
        // cinema ticket is not, so the word carries no category on its own.
        // An unmatched line already falls through to .other, which is the
        // right answer for the cinema case anyway.
        (.other, ["service charge", "tip", "entry", "entrance",
                  "guide", "spa", "massage", "laundry", "sim", "recharge",
                  "pharmacy", "medicine", "souvenir", "donation",
                  "insurance"])
    ]

    /// Internal rather than private so the fallback can be tested on its own.
    /// Testing it through `category(for:)` would measure whichever path
    /// happened to run, which changes depending on whether the model shipped.
    static func keywordCategory(for name: String) -> SpendingCategory {
        // Longest match wins, so "ice cream" beats a stray "cream" and
        // "service charge" is not read as food.
        var best: (category: SpendingCategory, length: Int)?

        for (category, terms) in keywords {
            for term in terms where name.contains(term) {
                if best == nil || term.count > best!.length {
                    best = (category, term.count)
                }
            }
        }

        return best?.category ?? .other
    }

    private static func normalise(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    // MARK: - Corrections

    private enum CorrectionStore {
        private static let key = "categoryCorrections"

        private static var all: [String: String] {
            UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        }

        static func category(for normalisedName: String) -> SpendingCategory? {
            guard let raw = all[normalisedName] else { return nil }
            return SpendingCategory(rawValue: raw)
        }

        static func save(_ category: SpendingCategory, for normalisedName: String) {
            guard !normalisedName.isEmpty else { return }
            var corrections = all
            corrections[normalisedName] = category.rawValue
            UserDefaults.standard.set(corrections, forKey: key)
        }

        static func clear() {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
