import WidgetKit
import SwiftUI

// MARK: - Timeline

struct BalanceEntry: TimelineEntry {
    let date: Date
    let snapshot: BalanceSnapshot
}

struct BalanceProvider: TimelineProvider {

    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        // The gallery preview shows sample figures; a real install shows real ones.
        let snapshot = context.isPreview ? BalanceSnapshot.placeholder : WidgetBridge.read()
        completion(BalanceEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        let entry = BalanceEntry(date: Date(), snapshot: WidgetBridge.read())

        // Balances only change when the app changes them, and the app reloads
        // the timeline itself when that happens. The periodic refresh is just
        // a safety net in case a reload is missed.
        let nextCheck = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextCheck)))
    }
}

// MARK: - Views

struct SplitLKWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BalanceEntry

    var body: some View {
        switch family {
        case .systemSmall: smallView
        default:           mediumView
        }
    }

    // MARK: Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("SplitLK", systemImage: "equal.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if entry.snapshot.isSettled {
                Text("All settled")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                amountBlock(title: "You're owed",
                            amount: entry.snapshot.owedToMe,
                            tint: .green)
                amountBlock(title: "You owe",
                            amount: entry.snapshot.iOwe,
                            tint: .red)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func amountBlock(title: String, amount: Decimal, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(format(amount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(amount == 0 ? .secondary : tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Medium

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("SplitLK", systemImage: "equal.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !entry.snapshot.isSettled {
                    Text(summaryLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if entry.snapshot.groups.isEmpty {
                Spacer()
                Text("No groups yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.snapshot.groups.prefix(3)) { group in
                    HStack {
                        Text(group.name)
                            .font(.footnote)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(label(for: group.balance))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(tint(for: group.balance))
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibleLabel(for: group))
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Helpers

    private var summaryLine: String {
        let net = entry.snapshot.net
        if net > 0 { return "owed \(format(net))" }
        if net < 0 { return "owe \(format(abs(net)))" }
        return "settled"
    }

    private func label(for balance: Decimal) -> String {
        if balance == 0 { return "Settled" }
        return (balance > 0 ? "+" : "−") + format(abs(balance))
    }

    private func tint(for balance: Decimal) -> Color {
        if balance == 0 { return .secondary }
        return balance > 0 ? .green : .red
    }

    private func accessibleLabel(for group: BalanceSnapshot.GroupSummary) -> String {
        if group.balance == 0 { return "\(group.name), settled up" }
        return group.balance > 0
            ? "\(group.name), you are owed \(format(group.balance))"
            : "\(group.name), you owe \(format(abs(group.balance)))"
    }

    /// The widget has its own copy rather than importing the app's Money
    /// helper, so the extension stays free of the app's model layer.
    private func format(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = amount == amount.rounded0 ? 0 : 2
        formatter.minimumFractionDigits = 0
        let number = NSDecimalNumber(decimal: amount)
        return "Rs " + (formatter.string(from: number) ?? "\(amount)")
    }
}

private extension Decimal {
    /// The value with no fractional part, used to decide whether to show cents.
    var rounded0: Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }
}

// MARK: - Widget

struct SplitLKWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.widgetKind,
                            provider: BalanceProvider()) { entry in
            SplitLKWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Balances")
        .description("What you're owed and what you owe across your groups.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    SplitLKWidget()
} timeline: {
    BalanceEntry(date: Date(), snapshot: .placeholder)
    BalanceEntry(date: Date(), snapshot: .empty)
}
