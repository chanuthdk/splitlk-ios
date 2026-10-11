import SwiftUI
import CoreData

struct GroupsView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDGroup.createdAt, ascending: false)],
        predicate: NSPredicate(format: "isArchived == NO"),
        animation: .default
    ) private var groups: FetchedResults<CDGroup>

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    emptyState
                } else {
                    groupList
                }
            }
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        SeedData.createIfNeeded(in: context)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a group")
                }
            }
        }
    }

    // MARK: - Pieces

    private var groupList: some View {
        List {
            Section {
                summaryCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section("Your Groups") {
                ForEach(groups) { group in
                    NavigationLink {
                        GroupDetailView(group: group)
                    } label: {
                        GroupRow(group: group)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var summaryCard: some View {
        HStack(spacing: 24) {
            balanceColumn(title: "You're owed", amount: totalOwedToMe, tint: .green)
            Divider()
            balanceColumn(title: "You owe", amount: totalIOwe, tint: .red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func balanceColumn(title: String, amount: Decimal, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(Money.format(amount))
                .font(.headline)
                .foregroundStyle(amount == 0 ? .secondary : tint)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No groups yet")
                .font(.title2.bold())
            Text("Create a group for a trip, a flat or a night out, then scan your first bill to start splitting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Create a Group") {
                SeedData.createIfNeeded(in: context)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }

    // MARK: - Totals

    private var totalOwedToMe: Decimal {
        groups.reduce(0) { sum, group in
            let balance = BalanceService.myBalance(in: group)
            return balance > 0 ? sum + balance : sum
        }
    }

    private var totalIOwe: Decimal {
        groups.reduce(0) { sum, group in
            let balance = BalanceService.myBalance(in: group)
            return balance < 0 ? sum + abs(balance) : sum
        }
    }
}

struct GroupRow: View {
    @ObservedObject var group: CDGroup

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: "4F46E5").opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "4F46E5"))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayName)
                    .font(.body)
                Text("\(group.memberList.count) members · \(group.billList.count) bills")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(balanceLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(balanceTint)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.displayName), \(accessibleBalance)")
    }

    private var balance: Decimal { BalanceService.myBalance(in: group) }

    private var balanceLabel: String {
        if balance == 0 { return "Settled up" }
        let prefix = balance > 0 ? "+" : "−"
        return prefix + Money.format(abs(balance))
    }

    private var balanceTint: Color {
        if balance == 0 { return .secondary }
        return balance > 0 ? .green : .red
    }

    private var accessibleBalance: String {
        if balance == 0 { return "settled up" }
        return balance > 0 ? "you are owed \(Money.format(balance))" : "you owe \(Money.format(abs(balance)))"
    }
}
