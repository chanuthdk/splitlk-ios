import SwiftUI
import CoreData

struct GroupsView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDGroup.createdAt, ascending: false)],
        predicate: NSPredicate(format: "isArchived == NO"),
        animation: .default
    ) private var groups: FetchedResults<CDGroup>

    @Environment(SyncService.self) private var sync

    @State private var showingCreateGroup = false
    @State private var showingJoinGroup = false
    @State private var selection: CDGroup?

    var body: some View {
        // A split view gives iPad a persistent sidebar beside the open group,
        // and collapses to a plain push navigation on iPhone, so both layouts
        // come from one definition rather than two parallel view trees.
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        // The groups list is where every change eventually lands, so this is
        // the one place that reliably sees a balance move.
        .onChange(of: snapshotKey) { _, _ in
            BalanceService.refreshWidget(with: Array(groups))
        }
        .task { BalanceService.refreshWidget(with: Array(groups)) }
        .sheet(isPresented: $showingCreateGroup) {
            CreateGroupView()
        }
        .sheet(isPresented: $showingJoinGroup) {
            JoinGroupView(sync: sync)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Group {
            if groups.isEmpty {
                emptyState
            } else {
                groupList
            }
        }
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Group", systemImage: "plus") {
                        showingCreateGroup = true
                    }
                    Button("Join with a Code", systemImage: "person.badge.key") {
                        showingJoinGroup = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add or join a group")
            }
        }
    }

    private var groupList: some View {
        List(selection: $selection) {
            Section {
                summaryCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section("Your Groups") {
                ForEach(groups) { group in
                    GroupRow(group: group, balance: myBalances[group.groupID] ?? 0)
                        .tag(group)
                        .swipeActions(edge: .trailing) {
                            Button("Archive", systemImage: "archivebox") {
                                archive(group)
                            }
                            .tint(.orange)
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selection, !selection.isDeleted {
            GroupDetailView(group: selection)
        } else {
            ContentUnavailableView(
                "No group selected",
                systemImage: "person.3",
                description: Text("Pick a group to see its bills and balances.")
            )
        }
    }

    // MARK: - Pieces

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
                showingCreateGroup = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Button("Join with a code") {
                showingJoinGroup = true
            }
            .font(.subheadline)
            .padding(.top, 2)

            Button("Load sample data") {
                SeedData.createIfNeeded(in: context)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
    }

    // MARK: - Actions

    private func archive(_ group: CDGroup) {
        if selection == group { selection = nil }
        group.isArchived = true
        do {
            try context.save()
        } catch {
            context.rollback()
        }
    }

    // MARK: - Totals

    /// Every balance is computed once per redraw and shared between the
    /// summary card and the rows. Reading `myBalance` inside each row instead
    /// would recompute the whole group's ledger several times over.
    private var myBalances: [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        for group in groups {
            result[group.groupID] = BalanceService.myBalance(in: group)
        }
        return result
    }

    private var totalOwedToMe: Decimal {
        myBalances.values.filter { $0 > 0 }.reduce(0, +)
    }

    private var totalIOwe: Decimal {
        myBalances.values.filter { $0 < 0 }.reduce(0) { $0 + abs($1) }
    }

    /// Changes whenever a balance could have moved, so the widget refresh
    /// fires on a new bill or settlement as well as on a new group.
    private var snapshotKey: String {
        groups.map { "\($0.groupID)-\($0.billList.count)-\($0.settlementList.count)" }
            .joined(separator: "|")
    }
}

struct GroupRow: View {
    @ObservedObject var group: CDGroup
    let balance: Decimal

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
        .accessibilityLabel("\(group.displayName), \(group.memberList.count) members, \(accessibleBalance)")
    }

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
