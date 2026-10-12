import SwiftUI
import CoreData

struct SettleUpView: View {
    @ObservedObject var group: CDGroup
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var transfers: [Transfer] = []

    var body: some View {
        List {
            if transfers.isEmpty {
                ContentUnavailableView(
                    "All settled up",
                    systemImage: "checkmark.circle",
                    description: Text("Nobody owes anybody in this group.")
                )
            } else {
                Section {
                    ForEach(Array(transfers.enumerated()), id: \.offset) { _, transfer in
                        TransferRow(transfer: transfer, group: group) {
                            record(transfer)
                        }
                    }
                } header: {
                    Text("\(transfers.count) payment\(transfers.count == 1 ? "" : "s") will clear all balances")
                }
            }
        }
        .navigationTitle("Settle Up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        transfers = BalanceService.transfers(for: group)
    }

    /// Stores the payment so it offsets the balances from now on.    private func record(_ transfer: Transfer) {
    /// Stores the payment so it offsets the balances from now on.
    private func record(_ transfer: Transfer) {
        print("looking for \(transfer.from) and \(transfer.to)")
        print("members: \(group.memberList.map { ($0.displayName, $0.id as Any) })")

        guard let from = group.member(with: transfer.from),
              let to = group.member(with: transfer.to) else { return }
        guard transfer.amount > 0 else { return }
        let settlement = CDSettlement(context: context)
        settlement.id = UUID()
        settlement.amount = NSDecimalNumber(decimal: transfer.amount)
        settlement.date = Date()
        settlement.fromMember = from
        settlement.toMember = to
        settlement.group = group

        do {
            try context.save()
            print("Settlements now: \(group.settlementList.count)")
            refresh()
        } catch {
            print("Settlement save failed: \(error)")
            context.rollback()
        }
    }
}

struct TransferRow: View {
    let transfer: Transfer
    @ObservedObject var group: CDGroup
    let onPaid: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let from = group.member(with: transfer.from) {
                    MemberAvatar(member: from, size: 32)
                }
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let to = group.member(with: transfer.to) {
                    MemberAvatar(member: to, size: 32)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(description)
                    .font(.headline)
                Text(Money.format(transfer.amount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Mark as Paid", action: onPaid)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(description), \(Money.format(transfer.amount))")
    }

    private var description: String {
        let from = group.member(with: transfer.from)?.displayName ?? "Someone"
        let to = group.member(with: transfer.to)?.displayName ?? "someone"
        return "\(from) pays \(to)"
    }
}
