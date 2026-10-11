import Foundation
import CoreData

enum SeedData {

    /// Creates a demo group once, so the app has something to show before scanning works.
    static func createIfNeeded(in context: NSManagedObjectContext) {
        let request = NSFetchRequest<CDGroup>(entityName: "CDGroup")
        request.fetchLimit = 1
        let existing = (try? context.count(for: request)) ?? 0
        guard existing == 0 else { return }

        let group = CDGroup(context: context)
        group.id = UUID()
        group.name = "Galle Trip"
        group.currencyCode = "LKR"
        group.createdAt = Date()
        group.isArchived = false

        let me = member(named: "Chanuth", color: "4F46E5", isMe: true, in: context)
        let nimal = member(named: "Nimal", color: "16A34A", isMe: false, in: context)
        let kasun = member(named: "Kasun", color: "D97706", isMe: false, in: context)
        let dilini = member(named: "Dilini", color: "DC2626", isMe: false, in: context)

        for person in [me, nimal, kasun, dilini] {
            person.group = group
        }

        addBill(merchant: "Lagoon Restaurant",
                payer: nimal,
                items: [("Chicken Kottu", 1200, .food, [me]),
                        ("Seafood Rice", 1850, .food, [nimal]),
                        ("Lime Juice", 400, .drinks, [kasun]),
                        ("Watalappan", 337, .food, [dilini])],
                serviceCharge: 378,
                group: group,
                in: context)

        addBill(merchant: "Tuk-tuk to Unawatuna",
                payer: kasun,
                items: [("Fare", 1200, .transport, [me, nimal, kasun, dilini])],
                serviceCharge: 0,
                group: group,
                in: context)

        try? context.save()
    }

    private static func member(named name: String,
                               color: String,
                               isMe: Bool,
                               in context: NSManagedObjectContext) -> CDMember {
        let member = CDMember(context: context)
        member.id = UUID()
        member.name = name
        member.colorHex = color
        member.isMe = isMe
        return member
    }

    private static func addBill(merchant: String,
                                payer: CDMember,
                                items: [(String, Decimal, SpendingCategory, [CDMember])],
                                serviceCharge: Decimal,
                                group: CDGroup,
                                in context: NSManagedObjectContext) {
        let bill = CDBill(context: context)
        bill.id = UUID()
        bill.merchant = merchant
        bill.date = Date()
        bill.group = group
        bill.payer = payer
        bill.splitModeRaw = SplitMode.byItem.rawValue
        bill.serviceCharge = NSDecimalNumber(decimal: serviceCharge)
        bill.tax = 0

        var subtotal: Decimal = 0
        for (name, amount, category, assignees) in items {
            let item = CDItem(context: context)
            item.id = UUID()
            item.name = name
            item.amount = NSDecimalNumber(decimal: amount)
            item.categoryRaw = category.rawValue
            item.wasEdited = false
            item.bill = bill
            subtotal += amount

            for assignee in assignees {
                let share = CDItemShare(context: context)
                share.id = UUID()
                share.weight = 1
                share.item = item
                share.member = assignee
            }
        }

        bill.subtotal = NSDecimalNumber(decimal: subtotal)
        bill.total = NSDecimalNumber(decimal: subtotal + serviceCharge)
    }
}
