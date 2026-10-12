import Foundation
import CoreGraphics

/// Turns recognised text lines into a structured bill.
/// Receipts are not consistently formatted, so this works on cues:
/// a row carrying a number is a candidate, keywords identify the
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
    private static let serviceKeywords = ["service", "serv charge", "s.charge", "svc"]
    private static let taxKeywords = ["vat", "tax", "gst", "ssl", "sscl", "nbt", "tdl"]
    private static let noiseKeywords = ["tel", "phone", "fax", "www", "http", "no.", "nic",
                                        "thank", "welcome", "cashier", "invoice no", "receipt",
                                        "bill no", "table", "date", "time", "change", "cash",
                                        "card", "visa", "master", "qty", "reg", "covers",
                                        "round of", "roundoff", "pay:", "pay :", "vat no",
                                        "powered by", "feedback", "mail@", "total qty",
                                        "item", "amt"]

    // MARK: - Row grouping
    /// Vision returns each column as its own line, so a receipt laid out in
    /// columns gives "Chicken strips", "1" and "1700.00" separately.
    /// Fragments are grouped by the TOP edge of their box rather than the
    /// centre: digits and capitals share a cap height, while descenders in a
    /// word like "Watalappan" drag its centre half a line below the amount
    /// printed beside it, which made centre-based grouping flip between runs.
    static func groupIntoRows(_ lines: [ReceiptScanner.Line]) -> [ReceiptScanner.Line] {
        // Rules of dashes carry no information and distort row bands.
        let content = lines.filter { line in
            !line.text.trimmingCharacters(in: CharacterSet(charactersIn: "-_=. ")).isEmpty
        }
        guard !content.isEmpty else { return [] }

        let heights = content.map(\.box.height).sorted()
        let medianHeight = heights[heights.count / 2]
        let tolerance = max(medianHeight * 0.5, 0.004)

        // Vision's origin is bottom-left, so a larger maxY is higher up the page.
        let sorted = content.sorted { $0.box.maxY > $1.box.maxY }

        var rows: [[ReceiptScanner.Line]] = []
        var current: [ReceiptScanner.Line] = [sorted[0]]
        var anchor = sorted[0].box.maxY

        for line in sorted.dropFirst() {
            if abs(line.box.maxY - anchor) < tolerance {
                current.append(line)
                anchor = current.map(\.box.maxY).reduce(0, +) / CGFloat(current.count)
            } else {
                rows.append(current)
                current = [line]
                anchor = line.box.maxY
            }
        }
        rows.append(current)

        let merged = rows.map { row -> ReceiptScanner.Line in
            let ordered = row.sorted { $0.box.minX < $1.box.minX }
            let text = ordered.map(\.text).joined(separator: " ")
            let box = ordered.dropFirst().reduce(ordered[0].box) { $0.union($1.box) }
            let confidence = ordered.map(\.confidence).min() ?? 0
            return ReceiptScanner.Line(text: text, box: box, confidence: confidence)
        }

        return repairOrphanAmounts(merged)
    }

    /// Safety net for a column that still lands in a row of its own: an
    /// amount with no words is folded back into the preceding row when that
    /// row has words but no amount.
    private static func repairOrphanAmounts(_ rows: [ReceiptScanner.Line]) -> [ReceiptScanner.Line] {
        func hasLetters(_ text: String) -> Bool { text.contains { $0.isLetter } }
        func hasDigits(_ text: String) -> Bool { text.contains { $0.isNumber } }

        var result: [ReceiptScanner.Line] = []
        for row in rows {
            if !hasLetters(row.text), hasDigits(row.text),
               let previous = result.last,
               hasLetters(previous.text), !hasDigits(previous.text) {
                result[result.count - 1] = ReceiptScanner.Line(
                    text: previous.text + " " + row.text,
                    box: previous.box.union(row.box),
                    confidence: min(previous.confidence, row.confidence)
                )
            } else {
                result.append(row)
            }
        }
        return result
    }
    // MARK: - Parsing

    static func parse(lines rawLines: [ReceiptScanner.Line]) -> ParsedReceipt {
        let lines = groupIntoRows(rawLines)

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

            // Checked first: "total qty" contains "total", so the noise filter
            // has to run before the keyword branches below.
            if noiseKeywords.contains(where: lower.contains) {
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
            if totalKeywords.contains(where: lower.contains) {
                // Receipts often print several totals; the largest is the real one.
                total = max(total ?? 0, value)
                continue
            }

            let name = itemName(from: text)
            // A price on a receipt is either written with cents or is at least
            // two digits. A bare single digit is a quantity or a stray number
            // from an address line, not an amount.
            let looksLikePrice = text.contains(".") || value >= 10
            guard name.count >= 2, value > 0, looksLikePrice else { continue }
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

    /// All numbers on a row, with their position, so the price can be taken
    /// as the rightmost value rather than assuming it ends the line.
    private static func numbers(in text: String) -> [(value: Decimal, range: Range<String.Index>)] {
        let pattern = #"\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            let cleaned = text[r]
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: " ", with: "")
            guard let value = Decimal(string: cleaned), value > 0, value < 1_000_000 else { return nil }
            return (value, r)
        }
    }

    /// The price on a row is the last number on it. A quantity column sits to
    /// the left of the amount, so taking the rightmost value skips it.
    static func amount(in text: String) -> Decimal? {
        numbers(in: text).last?.value
    }

    /// Everything before the first number is the item name; the quantity
    /// and price columns both follow it.
    private static func itemName(from text: String) -> String {
        let found = numbers(in: text)

        guard let firstNumber = found.first else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let name = String(text[text.startIndex..<firstNumber.range.lowerBound])

        // Drop a leading quantity marker such as "2 x " or "1."
        let withoutQty = name.replacingOccurrences(
            of: #"^\s*\d+\s*[xX\.\)]\s*"#, with: "", options: .regularExpression
        )

        return withoutQty
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-:"))
    }
}
