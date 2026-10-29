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
                    // The card draws its own background, so the row's inset
                    // and fill are cleared to let it sit edge to edge.
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
        // The system's grouped grey is replaced by the paper token, which is
        // what carries the receipt direction. Without this the palette only
        // shows up in the small details and the screen still reads as stock.
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
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

    /// The one number that answers "where do I stand" is given the size to
    /// match, with the two halves it is made of underneath. The previous
    /// version showed owed and owe as equal columns, which left the reader
    /// to do the subtraction.
    /// The total at the foot of a bill: the one figure, then a tear line, then
    /// the two amounts it was worked out from. Colour is carried by the figure
    /// itself rather than by a tinted panel, so the card stays paper and the
    /// number is the only thing competing for attention.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(netTitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.inkSoft)

                Text(Money.format(abs(netBalance)))
                    .font(.money(size: 34, weight: .semibold))
                    .foregroundStyle(netTint)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: netBalance)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            if totalOwedToMe > 0 || totalIOwe > 0 {
                TearLine()

                HStack(spacing: 20) {
                    supportingFigure(title: "Owed to you", amount: totalOwedToMe, tint: Palette.owed)
                    supportingFigure(title: "You owe", amount: totalIOwe, tint: Palette.owing)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Palette.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Palette.rule, lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibleSummary)
    }

    private func supportingFigure(title: String, amount: Decimal, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Palette.inkSoft)
            Text(Money.format(amount))
                .font(.money(.subheadline))
                .foregroundStyle(amount == 0 ? Palette.inkSoft : tint)
                .contentTransition(.numericText())
                .animation(.snappy, value: amount)
        }
    }

    private var netBalance: Decimal { totalOwedToMe - totalIOwe }

    private var netTitle: String {
        if netBalance > 0 { return "You're owed overall" }
        if netBalance < 0 { return "You owe overall" }
        return "All settled up"
    }

    private var netTint: Color {
        if netBalance > 0 { return Palette.owed }
        if netBalance < 0 { return Palette.owing }
        return Palette.inkSoft
    }

    private var accessibleSummary: String {
        if netBalance == 0 { return "All settled up" }
        let direction = netBalance > 0 ? "You are owed" : "You owe"
        return "\(direction) \(Money.format(abs(netBalance))) overall. "
            + "Owed to you \(Money.format(totalOwedToMe)), you owe \(Money.format(totalIOwe))."
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
                .fill(tint.gradient)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: group.displayIconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
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
                .font(.money(.subheadline))
                .foregroundStyle(balanceTint)
                .contentTransition(.numericText())
                .animation(.snappy, value: balance)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.displayName), \(group.memberList.count) members, \(accessibleBalance)")
    }

    /// Groups created before the colour picker existed have no stored colour,
    /// so one is derived from the name instead of leaving them all indigo.
    private var tint: Color {
        Color(hex: group.colorHex ?? GroupStyle.fallbackColorHex(for: group.displayName))
    }

    private var balanceLabel: String {
        if balance == 0 { return "Settled up" }
        let prefix = balance > 0 ? "+" : "−"
        return prefix + Money.format(abs(balance))
    }

    private var balanceTint: Color {
        if balance == 0 { return Palette.inkSoft }
        return balance > 0 ? Palette.owed : Palette.owing
    }

    private var accessibleBalance: String {
        if balance == 0 { return "settled up" }
        return balance > 0 ? "you are owed \(Money.format(balance))" : "you owe \(Money.format(abs(balance)))"
    }
}
