import Foundation
import CoreData

/// Converts stored bills into the pure domain types the calculators work on,
/// so the maths never has to know about Core Data.
enum BalanceService {

    static func splitInput(for bill: CDBill) -> SplitInput {
        let participants = bill.group?.memberList.map(\.memberID) ?? []

        let items = bill.itemList.map { item -> SplitItem in
            var assignments: [UUID: Decimal] = [:]
            for share in item.shareList {
                guard let member = share.member else { continue }
                assignments[member.memberID] = Decimal(share.weight)
            }
            return SplitItem(id: item.itemID,
                             name: item.displayName,
                             amount: item.itemAmount,
                             assignments: assignments)
        }

        var custom: [UUID: Decimal] = [:]
        for share in bill.customShareList {
            guard let member = share.member else { continue }
            custom[member.memberID] = share.shareAmount
        }

        return SplitInput(participants: participants,
                          items: items,
                          serviceCharge: bill.serviceChargeAmount,
                          tax: bill.taxAmount,
                          mode: bill.splitMode,
                          customAmounts: custom)
    }

    /// Net position per member. Positive means they are owed money.
    static func balances(for group: CDGroup) -> [UUID: Decimal] {
        var bills: [(payer: UUID, total: Decimal, shares: [UUID: Decimal])] = []

        for bill in group.billList {
            guard let payer = bill.payer else { continue }
            let shares = (try? SplitCalculator.shares(for: splitInput(for: bill))) ?? [:]
            bills.append((payer: payer.memberID, total: bill.totalAmount, shares: shares))
        }

        let settled: [Transfer] = group.settlementList.compactMap { settlement in
            guard let from = settlement.fromMember, let to = settlement.toMember else { return nil }
            return Transfer(from: from.memberID, to: to.memberID, amount: settlement.settlementAmount)
        }

        var result = SettlementCalculator.balances(bills: bills, settlements: settled)
        for member in group.memberList where result[member.memberID] == nil {
            result[member.memberID] = 0
        }
        return result
    }

    static func transfers(for group: CDGroup) -> [Transfer] {
        SettlementCalculator.minimalTransfers(balances: balances(for: group))
    }

    /// What the current user is owed, or owes, in this group.
    static func myBalance(in group: CDGroup) -> Decimal {
        guard let me = group.memberList.first(where: { $0.isMe }) else { return 0 }
        return balances(for: group)[me.memberID] ?? 0
    }

    /// Builds the summary the Home Screen widget reads, and hands it over.
    /// Called after anything that moves a balance, so the widget never shows
    /// a figure the app itself has already superseded.
    static func refreshWidget(with groups: [CDGroup]) {
        var summaries: [BalanceSnapshot.GroupSummary] = []
        var owedToMe: Decimal = 0
        var iOwe: Decimal = 0

        for group in groups where !group.isArchived {
            let balance = myBalance(in: group)
            if balance > 0 { owedToMe += balance }
            if balance < 0 { iOwe += abs(balance) }

            summaries.append(BalanceSnapshot.GroupSummary(id: group.groupID,
                                                          name: group.displayName,
                                                          balance: balance))
        }

        // Largest debts and credits first: a widget shows only a few rows,
        // so the ones worth chasing should be the ones that fit.
        summaries.sort { abs($0.balance) > abs($1.balance) }

        WidgetBridge.write(BalanceSnapshot(owedToMe: owedToMe,
                                           iOwe: iOwe,
                                           groups: summaries,
                                           updatedAt: Date()))
    }
}
