import Foundation

/// Turns recognised text lines into a structured bill.
/// Receipts are not consistently formatted, so this works on cues:
/// a trailing amount makes a line a candidate, keywords identify the
/// totals block, and anything that fits neither is discarded.
enum ReceiptParser {

    struct ParsedItem {
        var name: String
        var amount: Decimal
    }

    struct ParsedReceipt {
        var merchant: String?
        var items: [ParsedItem]
        var subtotal: Decimal?
        var serviceCharge: Decimal?
        var tax: Decimal?
        var total: Decimal?

        var itemsSum: Decimal { items.reduce(0) { $0 + $1.amount } }

        /// True when the parsed items plus charges match the printed total.
        /// A mismatch means something was misread, and the user is warned.
        var reconciles: Bool {
            guard let total else { return true }
            let computed = itemsSum + (serviceCharge ?? 0) + (tax ?? 0)
            return abs(computed - total) < 1
        }
    }

    private static let totalKeywords = ["total", "amount due", "grand total", "net amount", "balance due"]
    private static let subtotalKeywords = ["subtotal", "sub total", "sub-total"]
    private static let serviceKeywords = ["service", "s.charge", "svc"]
    private static let taxKeywords = ["vat", "tax", "gst", "ssl", "nbt"]
    private static let noiseKeywords = ["tel", "phone", "fax", "www", "http", "no.", "nic",
                                        "thank", "welcome", "cashier", "invoice", "receipt",
                                        "bill no", "table", "date", "time", "change", "cash",
                                        "card", "visa", "master", "qty", "reg"]

    static func parse(lines: [ReceiptScanner.Line]) -> ParsedReceipt {
        var items: [ParsedItem] = []
        var subtotal: Decimal?
        var service: Decimal?
        var tax: Decimal?
        var total: Decimal?

        // The merchant name is usually the first line with no amount on it.
        let merchant = lines.prefix(4)
            .first { amount(in: $0.text) == nil && $0.text.count > 3 }?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = text.lowercased()

            guard let value = amount(in: text) else { continue }

            if totalKeywords.contains(where: lower.contains) {
                // Receipts often print several totals; the largest is the real one.
                total = max(total ?? 0, value)
                continue
            }
            if subtotalKeywords.contains(where: lower.contains) {
                subtotal = value
                continue
            }
            if serviceKeywords.contains(where: lower.contains) {
                service = value
                continue
            }
            if taxKeywords.contains(where: lower.contains) {
                tax = (tax ?? 0) + value
                continue
            }
            if noiseKeywords.contains(where: lower.contains) {
                continue
            }

            let name = itemName(from: text)
            guard name.count >= 2, value > 0 else { continue }
            items.append(ParsedItem(name: name, amount: value))
        }

        // A total far below the item sum is usually a misread line, not a real total.
        if let t = total, t < items.reduce(0, { $0 + $1.amount }) / 2 {
            total = nil
        }

        return ParsedReceipt(merchant: merchant,
                             items: items,
                             subtotal: subtotal,
                             serviceCharge: service,
                             tax: tax,
                             total: total)
    }

    // MARK: - Helpers

    /// Pulls the trailing money value off a line, tolerating thousands separators,
    /// currency prefixes and OCR noise such as a stray trailing letter.
    static func amount(in text: String) -> Decimal? {
        let pattern = #"(\d{1,3}(?:[,\s]\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matched = Range(match.range(at: 1), in: text) else { return nil }

        let cleaned = text[matched]
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let value = Decimal(string: cleaned) else { return nil }
        // A bare year or quantity is not a price.
        guard value > 0, value < 1_000_000 else { return nil }
        return value
    }

    private static func itemName(from text: String) -> String {
        let pattern = #"\s*(?:Rs\.?|LKR)?\s*\d{1,3}(?:[,\s]\d{3})*(?:\.\d{1,2})?\s*$"#
        let name = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)

        // Drop a leading quantity marker such as "2 x " or "1."
        let withoutQty = name.replacingOccurrences(
            of: #"^\s*\d+\s*[xX\.\)]\s*"#, with: "", options: .regularExpression
        )

        return withoutQty.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
