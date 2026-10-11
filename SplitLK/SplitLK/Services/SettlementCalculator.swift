import Foundation

/// Reduces a group's debts to the fewest payments that clear everyone.
///
/// This is the minimum cash flow problem. Rather than settling each pair
/// separately, every member is netted to a single balance, then the largest
/// creditor is repeatedly matched against the largest debtor. Each match
/// zeroes at least one person, so a group of n settles in at most n-1 payments
/// instead of the n(n-1)/2 that pairwise settling could require.
enum SettlementCalculator {

    /// Positive balance means the member is owed money; negative means they owe.
    static func minimalTransfers(balances: [UUID: Decimal]) -> [Transfer] {
        // Work in integer cents so repeated subtraction cannot drift.
        var cents: [(id: UUID, amount: Int)] = balances.compactMap { id, value in
            let c = NSDecimalNumber(decimal: Money.round(value) * 100).intValue
            return c == 0 ? nil : (id, c)
        }
        guard !cents.isEmpty else { return [] }

        // Stable ordering keeps the output deterministic, which matters for tests.
        cents.sort { $0.amount == $1.amount ? $0.id.uuidString < $1.id.uuidString : $0.amount > $1.amount }

        var creditors = cents.filter { $0.amount > 0 }
        var debtors = cents.filter { $0.amount < 0 }.map { (id: $0.id, amount: -$0.amount) }
        debtors.sort { $0.amount == $1.amount ? $0.id.uuidString < $1.id.uuidString : $0.amount > $1.amount }

        var transfers: [Transfer] = []
        var i = 0, j = 0

        while i < creditors.count && j < debtors.count {
            let settled = min(creditors[i].amount, debtors[j].amount)

            transfers.append(Transfer(from: debtors[j].id,
                                      to: creditors[i].id,
                                      amount: Decimal(settled) / 100))

            creditors[i].amount -= settled
            debtors[j].amount -= settled

            if creditors[i].amount == 0 { i += 1 }
            if debtors[j].amount == 0 { j += 1 }
        }

        return transfers
    }

    /// Net position per member, given what each bill cost them and who paid it.
    static func balances(bills: [(payer: UUID, total: Decimal, shares: [UUID: Decimal])],
                         settlements: [Transfer] = []) -> [UUID: Decimal] {
        var balances: [UUID: Decimal] = [:]

        for bill in bills {
            balances[bill.payer, default: 0] += bill.total
            for (member, share) in bill.shares {
                balances[member, default: 0] -= share
            }
        }

        // A settled payment cancels part of what the payer owed.
        for transfer in settlements {
            balances[transfer.from, default: 0] += transfer.amount
            balances[transfer.to, default: 0] -= transfer.amount
        }

        return balances.mapValues { Money.round($0) }
    }
}
