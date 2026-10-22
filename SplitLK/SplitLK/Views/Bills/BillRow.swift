import SwiftUI

struct BillRow: View {
    @ObservedObject var bill: CDBill

    var body: some View {
        HStack(spacing: 12) {
            // The circle takes the dominant category's colour, which makes the
            // list scannable and shows the classifier's output without adding
            // a label for it.
            Image(systemName: dominantCategory.symbolName)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(dominantCategory.color))

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.displayMerchant)
                    .font(.body)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(Money.format(bill.totalAmount))
                .font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        // The colour carries the category for a sighted user, so it is named
        // here rather than left as decoration.
        .accessibilityLabel("\(bill.displayMerchant), \(dominantCategory.label), \(subtitle), \(Money.format(bill.totalAmount))")
    }

    private var subtitle: String {
        let payer = bill.payer?.displayName ?? "Unknown"
        let date = (bill.date ?? Date()).formatted(.dateTime.day().month(.abbreviated))
        return "Paid by \(payer) · \(date)"
    }

    /// The category most of the bill's money went to, used for the row icon.
    private var dominantCategory: SpendingCategory {
        var totals: [SpendingCategory: Decimal] = [:]
        for item in bill.itemList {
            totals[item.category, default: 0] += item.itemAmount
        }
        return totals.max { $0.value < $1.value }?.key ?? .other
    }
}
