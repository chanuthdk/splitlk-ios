import SwiftUI
import CoreData

struct GroupDetailView: View {
    @ObservedObject var group: CDGroup
    @Environment(\.managedObjectContext) private var context

    @State private var tab: Tab = .bills
    @State private var showingSettleUp = false
    @State private var showingAddBill = false

    enum Tab: String, CaseIterable, Identifiable {
        case bills, balances
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch tab {
            case .bills:    billsList
            case .balances: balancesList
            }
        }
        .navigationTitle(group.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddBill = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add a bill")
            }
        }
        .sheet(isPresented: $showingSettleUp) {
            NavigationStack {
                SettleUpView(group: group)
            }
        }
        .sheet(isPresented: $showingAddBill) {
            AddBillChooser(group: group)
        }
    }

    // MARK: - Bills

    private var billsList: some View {
        List {
            if group.billList.isEmpty {
                ContentUnavailableView(
                    "No bills yet",
                    systemImage: "doc.text",
                    description: Text("Scan a receipt or add a bill manually to start splitting.")
                )
            } else {
                ForEach(group.billList, id: \.billID) { bill in
                    BillRow(bill: bill)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Balances

    private var balancesList: some View {
        let balances = BalanceService.balances(for: group)
        let sorted = group.memberList.sorted {
            (balances[$0.memberID] ?? 0) > (balances[$1.memberID] ?? 0)
        }

        return List {
            Section {
                ForEach(sorted, id: \.memberID) { member in
                    BalanceRow(member: member,
                               amount: balances[member.memberID] ?? 0,
                               isMe: member.isMe)
                }
            } footer: {
                Text(netSummary(balances))
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Button {
                showingSettleUp = true
            } label: {
                Text("Settle Up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(16)
            .disabled(BalanceService.transfers(for: group).isEmpty)
        }
    }

    private func netSummary(_ balances: [UUID: Decimal]) -> String {
        guard let me = group.me, let mine = balances[me.memberID] else { return "" }
        if mine == 0 { return "You're all settled up in this group." }
        return mine > 0
            ? "Net: you're owed \(Money.format(mine)) in this group."
            : "Net: you owe \(Money.format(abs(mine))) in this group."
    }
}

struct BalanceRow: View {
    @ObservedObject var member: CDMember
    let amount: Decimal
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(member: member, size: 34)

            Text(label)
                .font(.body)

            Spacer()

            Text(amount == 0 ? "Settled" : Money.format(abs(amount)))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibleLabel)
    }

    private var label: String {
        if isMe { return "You" }
        if amount > 0 { return "\(member.displayName) is owed" }
        if amount < 0 { return "\(member.displayName) owes" }
        return member.displayName
    }

    private var tint: Color {
        if amount == 0 { return .secondary }
        return amount > 0 ? .green : .red
    }

    private var accessibleLabel: String {
        if amount == 0 { return "\(member.displayName), settled up" }
        return amount > 0
            ? "\(member.displayName) is owed \(Money.format(amount))"
            : "\(member.displayName) owes \(Money.format(abs(amount)))"
    }
}
