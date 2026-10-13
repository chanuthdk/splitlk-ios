import Testing
import Foundation
import CoreGraphics
@testable import SplitLK

/// Builds a fake recognised line so the parser can be tested without running
/// Vision. Boxes are in Vision's normalised, bottom-left origin space.
private func line(_ text: String,
                  x: CGFloat = 0.1,
                  y: CGFloat,
                  width: CGFloat = 0.3,
                  height: CGFloat = 0.02) -> ReceiptScanner.Line {
    ReceiptScanner.Line(text: text,
                        box: CGRect(x: x, y: y, width: width, height: height),
                        confidence: 0.9)
}

struct ReceiptParserTests {

    @Test("Columns on the same visual row are merged back into one line")
    func mergesColumns() {
        let lines = [
            line("Cheese Kottu", x: 0.1, y: 0.50),
            line("1",            x: 0.55, y: 0.50, width: 0.03),
            line("1,450.00",     x: 0.70, y: 0.50, width: 0.18)
        ]

        let rows = ReceiptParser.groupIntoRows(lines)
        #expect(rows.count == 1)
        #expect(rows[0].text == "Cheese Kottu 1 1,450.00")
    }

    @Test("Rows are kept apart when they sit on different lines")
    func keepsSeparateRowsApart() {
        let lines = [
            line("Cheese Kottu", y: 0.50),
            line("Iced Coffee",  y: 0.40)
        ]

        let rows = ReceiptParser.groupIntoRows(lines)
        #expect(rows.count == 2)
    }

    @Test("Descenders do not drag a name onto the row below")
    func descendersDoNotBreakGrouping() {
        // "Watalappan" has descenders, so Vision reports a taller box whose
        // centre sits lower than the digits printed beside it.
        let lines = [
            ReceiptScanner.Line(text: "Watalappan",
                                box: CGRect(x: 0.1, y: 0.492, width: 0.3, height: 0.028),
                                confidence: 0.9),
            line("2",      x: 0.55, y: 0.50, width: 0.03),
            line("700.00", x: 0.70, y: 0.50, width: 0.16)
        ]

        let rows = ReceiptParser.groupIntoRows(lines)
        #expect(rows.count == 1)
        #expect(rows[0].text.contains("Watalappan"))
        #expect(rows[0].text.contains("700.00"))
    }

    @Test("The price is the rightmost number, not the quantity")
    func priceIsRightmostNumber() {
        #expect(ReceiptParser.amount(in: "Chicken strips 1 1,700.00") == 1700)
        #expect(ReceiptParser.amount(in: "Watalappan 2 700.00") == 700)
    }

    @Test("A quantity glued to a price is not read as one number")
    func quantityIsNotPartOfPrice() {
        // "Bottled Water 1 180.00" must give 180, never 1,180.
        #expect(ReceiptParser.amount(in: "Bottled Water 1 180.00") == 180)
    }

    @Test("A full receipt parses into items, charges and a total")
    func parsesWholeReceipt() {
        var y: CGFloat = 0.90
        func next() -> CGFloat { defer { y -= 0.04 }; return y }

        let lines = [
            line("HILLTOP BAKE & BREW",         y: next()),
            line("Bill No: 02271",              y: next()),
            line("Covers: 3",                   y: next()),
            line("Cheese Kottu 1 1,450.00",     y: next()),
            line("Chicken Submarine 1 1,250.00", y: next()),
            line("Iced Coffee 2 1,100.00",      y: next()),
            line("Bottled Water 1 180.00",      y: next()),
            line("Total Qty: 5",                y: next()),
            line("Sub Total: 3,980.00",         y: next()),
            line("Service Charge 398.00",       y: next()),
            line("VAT 18% 788.04",              y: next()),
            line("Round Off: -0.04",            y: next()),
            line("Total Invoice Value 5,166",   y: next()),
            line("PAY: 5166",                   y: next()),
            line("VAT NO - 102933741",          y: next())
        ]

        let parsed = ReceiptParser.parse(lines: lines)

        #expect(parsed.items.count == 4)
        #expect(parsed.itemsSum == 3980)
        #expect(parsed.serviceCharge == 398)
        #expect(parsed.tax == 788.04)
        #expect(parsed.total == 5166)
        #expect(parsed.merchant == "HILLTOP BAKE & BREW")
    }

    @Test("Non-item lines are discarded rather than priced")
    func ignoresNoiseLines() {
        var y: CGFloat = 0.90
        func next() -> CGFloat { defer { y -= 0.04 }; return y }

        let lines = [
            line("Covers: 4",             y: next()),
            line("Total Qty: 8",          y: next()),
            line("Round Off: 0.65",       y: next()),
            line("PAY: 7556",             y: next()),
            line("VAT NO - 104872316",    y: next()),
            line("Devilled Chicken 1 1,850.00", y: next())
        ]

        let parsed = ReceiptParser.parse(lines: lines)
        #expect(parsed.items.count == 1)
        #expect(parsed.items.first?.amount == 1850)
    }

    @Test("A receipt whose items match the total reconciles")
    func reconcilesWhenConsistent() {
        let receipt = ReceiptParser.ParsedReceipt(
            merchant: "Test",
            items: [.init(name: "A", amount: 1000), .init(name: "B", amount: 500)],
            subtotal: 1500,
            serviceCharge: 150,
            tax: 0,
            total: 1650
        )
        #expect(receipt.reconciles)
    }

    @Test("A misread item is flagged by the reconciliation check")
    func failsReconciliationWhenItemMisread() {
        let receipt = ReceiptParser.ParsedReceipt(
            merchant: "Test",
            items: [.init(name: "A", amount: 1000), .init(name: "B", amount: 137)],
            subtotal: 1137,
            serviceCharge: 0,
            tax: 0,
            total: 1337
        )
        #expect(!receipt.reconciles)
    }

    @Test("A rounding line under one rupee does not trigger a warning")
    func roundingToleranceAllowsSmallGap() {
        // Items plus charges come to 7555.35 against a printed 7556: the
        // difference is the receipt's own Round Off line, not a misread.
        let receipt = ReceiptParser.ParsedReceipt(
            merchant: "Test",
            items: [.init(name: "A", amount: 5700)],
            subtotal: 5700,
            serviceCharge: 570,
            tax: 1285.35,
            total: 7556
        )
        #expect(receipt.reconciles)
    }
}

struct DuplicateDetectorTests {

    @Test("Fingerprints closer than the threshold are treated as duplicates")
    func closeFingerprintsMatch() {
        #expect(DuplicateDetector.isDuplicate(distance: 0))
        #expect(DuplicateDetector.isDuplicate(distance: DuplicateDetector.threshold - 0.1))
    }

    @Test("Fingerprints at or beyond the threshold are treated as different")
    func distantFingerprintsDoNotMatch() {
        #expect(!DuplicateDetector.isDuplicate(distance: DuplicateDetector.threshold))
        #expect(!DuplicateDetector.isDuplicate(distance: 40))
    }

    @Test("Confidence falls as the fingerprints grow further apart")
    func confidenceDecreasesWithDistance() {
        let near = DuplicateDetector.confidencePercent(for: 1)
        let far = DuplicateDetector.confidencePercent(for: 10)
        #expect(near > far)
    }

    @Test("Confidence stays within 0 and 100 at the extremes")
    func confidenceIsClamped() {
        #expect(DuplicateDetector.confidencePercent(for: 0) == 100)
        #expect(DuplicateDetector.confidencePercent(for: 999) == 0)
    }
}
