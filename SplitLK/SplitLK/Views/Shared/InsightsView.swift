import SwiftUI
import Charts
import CoreData

struct InsightsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDGroup.createdAt, ascending: false)],
        predicate: NSPredicate(format: "isArchived == NO")
    ) private var groups: FetchedResults<CDGroup>

    var body: some View {
        NavigationStack {
            Group {
                if categories.isEmpty {
                    ContentUnavailableView(
                        "Nothing to show yet",
                        systemImage: "chart.pie",
                        description: Text("Add a few bills and your spending breakdown will appear here.")
                    )
                } else {
                    List {
                        categorySection
                        monthlySection
                        topCategoriesSection
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Insights")
        }
    }

    // MARK: - Category breakdown

    private var categorySection: some View {
        Section("By Category") {
            VStack(alignment: .leading, spacing: 12) {
                Text(Money.format(total))
                    .font(.title2.bold())
                Text("your share across \(groups.count) group\(groups.count == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Chart(categories) { entry in
                    SectorMark(
                        angle: .value("Amount", (entry.amount as NSDecimalNumber).doubleValue),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(by: .value("Category", entry.category.label))
                }
                .frame(height: 200)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                .accessibilityLabel("Spending by category")
                .accessibilityValue(categoryAccessibilitySummary)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Monthly trend

    private var monthlySection: some View {
        Section("Last 6 Months") {
            VStack(alignment: .leading, spacing: 12) {
                if monthlyAverage > 0 {
                    Text("\(Money.format(monthlyAverage)) a month on average")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Chart(months) { entry in
                    BarMark(
                        x: .value("Month", entry.label),
                        y: .value("Amount", (entry.amount as NSDecimalNumber).doubleValue)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(Color(hex: "4F46E5"))
                }
                .frame(height: 160)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .accessibilityLabel("Monthly spending")
                .accessibilityValue(monthlyAccessibilitySummary)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Top categories

    private var topCategoriesSection: some View {
        Section("Top Categories") {
            ForEach(categories.prefix(4)) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.category.symbolName)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(hex: "4F46E5")))

                    Text(entry.category.label)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Money.format(entry.amount))
                            .font(.subheadline.weight(.medium))
                        if total > 0 {
                            Text("\(percent(entry.amount))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.category.label), \(Money.format(entry.amount)), \(percent(entry.amount)) percent")
            }
        }
    }

    // MARK: - Data

    private var groupArray: [CDGroup] { Array(groups) }
    private var categories: [InsightsService.CategoryTotal] {
        InsightsService.categoryTotals(for: groupArray)
    }
    private var months: [InsightsService.MonthTotal] {
        InsightsService.monthlyTotals(for: groupArray)
    }
    private var total: Decimal { InsightsService.grandTotal(categories) }

    private var monthlyAverage: Decimal {
        let spent = months.filter { $0.amount > 0 }
        guard !spent.isEmpty else { return 0 }
        return Money.round(spent.reduce(0) { $0 + $1.amount } / Decimal(spent.count))
    }

    private func percent(_ amount: Decimal) -> Int {
        guard total > 0 else { return 0 }
        let ratio = (amount / total * 100) as NSDecimalNumber
        return Int(ratio.doubleValue.rounded())
    }

    private var categoryAccessibilitySummary: String {
        categories.prefix(4)
            .map { "\($0.category.label) \(Money.format($0.amount))" }
            .joined(separator: ", ")
    }

    private var monthlyAccessibilitySummary: String {
        months.map { "\($0.label) \(Money.format($0.amount))" }
            .joined(separator: ", ")
    }
}
