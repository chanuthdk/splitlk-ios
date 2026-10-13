import Testing
import Foundation
import CoreData
@testable import SplitLK

/// These run against an in-memory store, so nothing touches the real
/// database and each test starts from a clean slate.
@MainActor
struct InsightsServiceTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    @discardableResult
    private func makeGroup(in context: NSManagedObjectContext,
                           memberNames: [String] = ["Me", "Nimal"]) -> CDGroup {
        let group = CDGroup(context: context)
        group.id = UUID()
        group.name = "Test Group"
        group.currencyCode = "LKR"
        group.createdAt = Date()
        group.isArchived = false

        for (index, name) in memberNames.enumerated() {
            let member = CDMember(context: context)
            member.id = UUID()
            member.name = name
            member.colorHex = "4F46E5"
            member.isMe = index == 0
            member.group = group
        }

        return group
    }

    private func addBill(to group: CDGroup,
                         in context: NSManagedObjectContext,
                         items: [(String, Decimal, SpendingCategory)],
                         date: Date = Date(),
                         mode: SplitMode = .equally) {
        let bill = CDBill(context: context)
        bill.id = UUID()
        bill.merchant = "Test Bill"
        bill.date = date
        bill.group = group
        bill.payer = group.me
        bill.splitModeRaw = mode.rawValue
        bill.serviceCharge = 0
        bill.tax = 0

        var subtotal: Decimal = 0
        for (index, entry) in items.enumerated() {
            let item = CDItem(context: context)
            item.id = UUID()
            item.name = entry.0
            item.amount = NSDecimalNumber(decimal: entry.1)
            item.categoryRaw = entry.2.rawValue
            item.wasEdited = false
            item.position = Int16(index)
            item.bill = bill
            subtotal += entry.1
        }

        bill.subtotal = NSDecimalNumber(decimal: subtotal)
        bill.total = NSDecimalNumber(decimal: subtotal)
    }

    @Test("Categories total the user's own share, not the whole bill")
    func categoryTotalsUseMyShare() {
        let context = makeContext()
        let group = makeGroup(in: context)

        // A 1000 bill split equally between two people is 500 to me.
        addBill(to: group, in: context, items: [("Kottu", 1000, .food)])

        let totals = InsightsService.categoryTotals(for: [group])
        #expect(totals.count == 1)
        #expect(totals.first?.category == .food)
        #expect(totals.first?.amount == 500)
    }

    @Test("Spending is split across the categories of the items")
    func categoriesAreSeparated() {
        let context = makeContext()
        let group = makeGroup(in: context)

        addBill(to: group, in: context, items: [
            ("Kottu", 600, .food),
            ("Tuk-tuk", 400, .transport)
        ])

        let totals = InsightsService.categoryTotals(for: [group])
        #expect(totals.count == 2)
        // Half of each, since the bill splits equally between two members.
        #expect(totals.first { $0.category == .food }?.amount == 300)
        #expect(totals.first { $0.category == .transport }?.amount == 200)
    }

    @Test("Categories come back largest first")
    func categoriesAreSortedBySize() {
        let context = makeContext()
        let group = makeGroup(in: context)

        addBill(to: group, in: context, items: [
            ("Water", 200, .drinks),
            ("Rice", 1800, .food)
        ])

        let totals = InsightsService.categoryTotals(for: [group])
        #expect(totals.first?.category == .food)
    }

    @Test("A group with no bills produces no categories")
    func emptyGroupHasNoTotals() {
        let context = makeContext()
        let group = makeGroup(in: context)
        #expect(InsightsService.categoryTotals(for: [group]).isEmpty)
    }

    @Test("Monthly totals cover the requested span, including empty months")
    func monthlyTotalsIncludeEmptyMonths() {
        let context = makeContext()
        let group = makeGroup(in: context)
        addBill(to: group, in: context, items: [("Kottu", 1000, .food)])

        let months = InsightsService.monthlyTotals(for: [group], months: 6)
        #expect(months.count == 6)
        // The newest bucket is the current month and holds this bill.
        #expect(months.last?.amount == 500)
        // Earlier months exist but are empty rather than missing.
        #expect(months.first?.amount == 0)
    }

    @Test("Bills in the same month are added together")
    func monthlyTotalsAccumulate() {
        let context = makeContext()
        let group = makeGroup(in: context)
        addBill(to: group, in: context, items: [("A", 1000, .food)])
        addBill(to: group, in: context, items: [("B", 500, .food)])

        let months = InsightsService.monthlyTotals(for: [group], months: 3)
        #expect(months.last?.amount == 750)
    }

    @Test("The grand total matches the sum of the categories")
    func grandTotalSumsCategories() {
        let context = makeContext()
        let group = makeGroup(in: context)
        addBill(to: group, in: context, items: [
            ("Kottu", 600, .food),
            ("Tuk-tuk", 400, .transport)
        ])

        let totals = InsightsService.categoryTotals(for: [group])
        #expect(InsightsService.grandTotal(totals) == 500)
    }
}

@MainActor
struct BalanceServiceTests {

    @Test("Recording a settlement clears the outstanding balance")
    func settlementClearsBalance() throws {
        let context = PersistenceController(inMemory: true).container.viewContext

        let group = CDGroup(context: context)
        group.id = UUID()
        group.name = "Trip"
        group.currencyCode = "LKR"
        group.createdAt = Date()
        group.isArchived = false

        let me = CDMember(context: context)
        me.id = UUID(); me.name = "Me"; me.colorHex = "4F46E5"; me.isMe = true; me.group = group

        let other = CDMember(context: context)
        other.id = UUID(); other.name = "Nimal"; other.colorHex = "16A34A"; other.isMe = false; other.group = group

        let bill = CDBill(context: context)
        bill.id = UUID(); bill.merchant = "Dinner"; bill.date = Date()
        bill.group = group; bill.payer = me
        bill.splitModeRaw = SplitMode.equally.rawValue
        bill.serviceCharge = 0; bill.tax = 0
        bill.subtotal = 1000; bill.total = 1000

        let item = CDItem(context: context)
        item.id = UUID(); item.name = "Food"; item.amount = 1000
        item.categoryRaw = SpendingCategory.food.rawValue
        item.wasEdited = false; item.position = 0; item.bill = bill

        try context.save()

        // I paid 1000 and consumed 500, so I am owed 500.
        #expect(BalanceService.myBalance(in: group) == 500)

        let settlement = CDSettlement(context: context)
        settlement.id = UUID()
        settlement.amount = 500
        settlement.date = Date()
        settlement.fromMember = other
        settlement.toMember = me
        settlement.group = group
        try context.save()

        #expect(BalanceService.myBalance(in: group) == 0)
    }

    @Test("Several settlements to the same person all count")
    func multipleSettlementsSurvive() throws {
        // Guards the one-to-one relationship bug: when CDMember.settlementsTo
        // was to-one, saving a second settlement silently detached the first.
        let context = PersistenceController(inMemory: true).container.viewContext

        let group = CDGroup(context: context)
        group.id = UUID(); group.name = "Trip"; group.currencyCode = "LKR"
        group.createdAt = Date(); group.isArchived = false

        let me = CDMember(context: context)
        me.id = UUID(); me.name = "Me"; me.colorHex = "4F46E5"; me.isMe = true; me.group = group

        let first = CDMember(context: context)
        first.id = UUID(); first.name = "A"; first.colorHex = "16A34A"; first.isMe = false; first.group = group

        let second = CDMember(context: context)
        second.id = UUID(); second.name = "B"; second.colorHex = "D97706"; second.isMe = false; second.group = group

        for payer in [first, second] {
            let settlement = CDSettlement(context: context)
            settlement.id = UUID()
            settlement.amount = 100
            settlement.date = Date()
            settlement.fromMember = payer
            settlement.toMember = me
            settlement.group = group
        }
        try context.save()

        #expect(group.settlementList.count == 2)
        #expect(group.settlementList.allSatisfy { $0.toMember != nil })
    }
}
