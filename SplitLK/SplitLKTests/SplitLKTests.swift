import Testing
import Foundation
@testable import SplitLK

struct MoneyTests {

    @Test("Dividing an indivisible amount still sums to the original")
    func divideRemainder() {
        let parts = Money.divide(1000, into: 3)
        #expect(parts.reduce(0, +) == 1000)
        #expect(parts == [333.34, 333.33, 333.33])
    }

    @Test("Allocation in proportion sums to the original")
    func allocateProportionally() {
        let parts = Money.allocate(100, proportionalTo: [1, 1, 1])
        #expect(parts.reduce(0, +) == 100)
    }

    @Test("Allocating against zero weights falls back to an equal split")
    func allocateZeroWeights() {
        let parts = Money.allocate(90, proportionalTo: [0, 0, 0])
        #expect(parts == [30, 30, 30])
    }
}

struct SplitCalculatorTests {

    let a = UUID(), b = UUID(), c = UUID()

    @Test("An equal split covers the full total")
    func equalSplit() throws {
        let input = SplitInput(participants: [a, b, c], items: [
            SplitItem(name: "Kottu", amount: 1200)
        ], serviceCharge: 120, tax: 0, mode: .equally)

        let shares = try SplitCalculator.shares(for: input)
        #expect(shares.values.reduce(0, +) == 1320)
        #expect(shares.count == 3)
    }

    @Test("By item, a member who consumed nothing pays nothing")
    func memberWhoAteNothing() throws {
        let input = SplitInput(participants: [a, b, c], items: [
            SplitItem(name: "Kottu", amount: 1200, assignments: [a: 1]),
            SplitItem(name: "Coke", amount: 300, assignments: [b: 1])
        ], mode: .byItem)

        let shares = try SplitCalculator.shares(for: input)
        #expect(shares[a] == 1200)
        #expect(shares[b] == 300)
        #expect(shares[c] == 0)
    }

    @Test("Service charge is shared in proportion to consumption, not flat")
    func serviceChargeIsProportional() throws {
        let input = SplitInput(participants: [a, b], items: [
            SplitItem(name: "Seafood platter", amount: 3000, assignments: [a: 1]),
            SplitItem(name: "Soup", amount: 1000, assignments: [b: 1])
        ], serviceCharge: 400, mode: .byItem)

        let shares = try SplitCalculator.shares(for: input)
        // a consumed 75% of the food, so carries 75% of the charge
        #expect(shares[a] == 3300)
        #expect(shares[b] == 1100)
        #expect(shares.values.reduce(0, +) == 4400)
    }

    @Test("A shared item is divided between its assignees")
    func sharedItem() throws {
        let input = SplitInput(participants: [a, b], items: [
            SplitItem(name: "Bottle of water", amount: 300, assignments: [a: 1, b: 1])
        ], mode: .byItem)

        let shares = try SplitCalculator.shares(for: input)
        #expect(shares[a] == 150)
        #expect(shares[b] == 150)
    }

    @Test("An unassigned item falls back to an equal split")
    func unassignedItem() throws {
        let input = SplitInput(participants: [a, b], items: [
            SplitItem(name: "Mystery charge", amount: 500)
        ], mode: .byItem)

        let shares = try SplitCalculator.shares(for: input)
        #expect(shares[a] == 250)
        #expect(shares[b] == 250)
    }

    @Test("Custom amounts must reconcile with the bill total")
    func customAmountsMustMatch() {
        let input = SplitInput(participants: [a, b], items: [
            SplitItem(name: "Dinner", amount: 1000)
        ], mode: .custom, customAmounts: [a: 600, b: 300])

        #expect(throws: SplitError.self) {
            try SplitCalculator.shares(for: input)
        }
    }

    @Test("A bill with no participants is rejected")
    func noParticipants() {
        let input = SplitInput(participants: [], mode: .equally)
        #expect(throws: SplitError.noParticipants) {
            try SplitCalculator.shares(for: input)
        }
    }
}

struct SettlementCalculatorTests {

    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test("Everyone square means no payments")
    func noTransfersWhenSettled() {
        let transfers = SettlementCalculator.minimalTransfers(balances: [a: 0, b: 0])
        #expect(transfers.isEmpty)
    }

    @Test("A single debt becomes one payment")
    func simpleDebt() {
        let transfers = SettlementCalculator.minimalTransfers(balances: [a: 500, b: -500])
        #expect(transfers.count == 1)
        #expect(transfers.first?.from == b)
        #expect(transfers.first?.to == a)
        #expect(transfers.first?.amount == 500)
    }

    @Test("Four members settle in at most three payments")
    func minimisesTransferCount() {
        let balances: [UUID: Decimal] = [a: 2450, b: -1250, c: -950, d: -250]
        let transfers = SettlementCalculator.minimalTransfers(balances: balances)

        #expect(transfers.count <= 3)
        let received = transfers.filter { $0.to == a }.reduce(Decimal(0)) { $0 + $1.amount }
        #expect(received == 2450)
    }

    @Test("Transfers always balance back to zero")
    func transfersConserveMoney() {
        let balances: [UUID: Decimal] = [a: 1500, b: 300, c: -1000, d: -800]
        let transfers = SettlementCalculator.minimalTransfers(balances: balances)

        var net: [UUID: Decimal] = balances
        for transfer in transfers {
            net[transfer.from, default: 0] += transfer.amount
            net[transfer.to, default: 0] -= transfer.amount
        }
        #expect(net.values.allSatisfy { $0 == 0 })
    }

    @Test("Balances follow from who paid and who consumed")
    func balancesFromBills() {
        let bills = [
            (payer: a, total: Decimal(3000), shares: [a: Decimal(1000), b: Decimal(1000), c: Decimal(1000)])
        ]
        let balances = SettlementCalculator.balances(bills: bills)

        #expect(balances[a] == 2000)
        #expect(balances[b] == -1000)
        #expect(balances[c] == -1000)
    }

    @Test("A recorded settlement reduces the outstanding balance")
    func settlementReducesBalance() {
        let bills = [
            (payer: a, total: Decimal(1000), shares: [a: Decimal(500), b: Decimal(500)])
        ]
        let paid = [Transfer(from: b, to: a, amount: 500)]
        let balances = SettlementCalculator.balances(bills: bills, settlements: paid)

        #expect(balances[a] == 0)
        #expect(balances[b] == 0)
    }
}
