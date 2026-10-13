import Foundation
import CoreData

/// Aggregates bills into the series the Insights charts draw.
/// Kept out of the view so the arithmetic can be tested directly.
enum InsightsService {

    struct CategoryTotal: Identifiable {
        let category: SpendingCategory
        let amount: Decimal
        var id: String { category.rawValue }
    }

    struct MonthTotal: Identifiable {
        let month: Date
        let amount: Decimal
        var id: Date { month }

        var label: String {
            month.formatted(.dateTime.month(.abbreviated))
        }
    }

    /// What the user personally owes across the given bills, broken down by
    /// category. Uses each bill's own split, so a member who skipped the
    /// drinks is not charged for them here either.
    static func categoryTotals(for groups: [CDGroup]) -> [CategoryTotal] {
        var totals: [SpendingCategory: Decimal] = [:]

        for group in groups {
            guard let me = group.me else { continue }

            for bill in group.billList {
                let input = BalanceService.splitInput(for: bill)
                guard let shares = try? SplitCalculator.shares(for: input),
                      let myShare = shares[me.memberID], myShare > 0 else { continue }

                let billTotal = bill.totalAmount
                guard billTotal > 0 else { continue }

                // The share covers the whole bill including charges, so each
                // item contributes in proportion to its price.
                for item in bill.itemList {
                    let portion = item.itemAmount / billTotal * myShare
                    totals[item.category, default: 0] += portion
                }
            }
        }

        return totals
            .map { CategoryTotal(category: $0.key, amount: Money.round($0.value)) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    /// The user's spending per calendar month, oldest first, with empty
    /// months included so the bars show gaps rather than silently closing them.
    static func monthlyTotals(for groups: [CDGroup],
                              months: Int = 6,
                              calendar: Calendar = .current,
                              now: Date = Date()) -> [MonthTotal] {
        var totals: [Date: Decimal] = [:]

        for group in groups {
            guard let me = group.me else { continue }

            for bill in group.billList {
                guard let date = bill.date else { continue }
                let input = BalanceService.splitInput(for: bill)
                guard let shares = try? SplitCalculator.shares(for: input),
                      let myShare = shares[me.memberID], myShare > 0 else { continue }

                let components = calendar.dateComponents([.year, .month], from: date)
                guard let bucket = calendar.date(from: components) else { continue }
                totals[bucket, default: 0] += myShare
            }
        }

        let currentComponents = calendar.dateComponents([.year, .month], from: now)
        guard let thisMonth = calendar.date(from: currentComponents) else { return [] }

        return (0..<months).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: thisMonth) else {
                return nil
            }
            return MonthTotal(month: month, amount: Money.round(totals[month] ?? 0))
        }
    }

    static func grandTotal(_ categories: [CategoryTotal]) -> Decimal {
        categories.reduce(0) { $0 + $1.amount }
    }
}
