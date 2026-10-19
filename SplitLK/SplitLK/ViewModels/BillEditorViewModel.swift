import Foundation
import CoreData
import SwiftUI

/// Holds a bill while it is being created or edited, before it is saved.
/// Kept separate from Core Data so a scan can populate the same draft.
@Observable
final class BillEditorViewModel {

    struct DraftItem: Identifiable {
        let id = UUID()
        var name: String = ""
        var amount: Decimal = 0
        var category: SpendingCategory = .food
        /// Member ids who consumed this item. Empty means unassigned.
        var assignees: Set<UUID> = []
    }

    var merchant: String = ""
    var date: Date = Date()
    var payerID: UUID?
    var items: [DraftItem] = []
    var serviceCharge: Decimal = 0
    var tax: Decimal = 0
    var mode: SplitMode = .byItem
    var scannedTotal: Decimal?
    var reconciles: Bool = true
    var receiptImage: Data?
    var featurePrint: Data?
    var rawOCRText: String?

    let group: CDGroup

    init(group: CDGroup) {
        self.group = group
        self.payerID = group.me?.memberID ?? group.memberList.first?.memberID
    }

    // MARK: - Derived values

    var itemsSubtotal: Decimal { items.reduce(0) { $0 + $1.amount } }
    var total: Decimal { itemsSubtotal + serviceCharge + tax }

    var canSave: Bool {
        !merchant.trimmingCharacters(in: .whitespaces).isEmpty
            && !items.isEmpty
            && payerID != nil
            && total > 0
    }

    var unassignedCount: Int {
        items.filter { $0.assignees.isEmpty }.count
    }

    // MARK: - Editing

    func addItem() {
        items.append(DraftItem())
    }

    func removeItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    /// Recategorising an item teaches the classifier, so the same line is
    /// filed the user's way on every later receipt.
    func setCategory(_ category: SpendingCategory, on itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].category = category
        CategoryClassifier.remember(category, for: items[index].name)
    }

    func toggle(_ memberID: UUID, on itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        if items[index].assignees.contains(memberID) {
            items[index].assignees.remove(memberID)
        } else {
            items[index].assignees.insert(memberID)
        }
    }

    func assignAll(to memberID: UUID) {
        for index in items.indices {
            items[index].assignees.insert(memberID)
        }
    }

    /// A live preview of what each member would owe, using the same
    /// calculator the saved bill will use.
    func previewShares() -> [UUID: Decimal] {
        let input = SplitInput(
            participants: group.memberList.map(\.memberID),
            items: items.map { draft in
                SplitItem(id: draft.id,
                          name: draft.name,
                          amount: draft.amount,
                          assignments: Dictionary(uniqueKeysWithValues: draft.assignees.map { ($0, Decimal(1)) }))
            },
            serviceCharge: serviceCharge,
            tax: tax,
            mode: mode
        )
        return (try? SplitCalculator.shares(for: input)) ?? [:]
    }

    // MARK: - Saving

    @discardableResult
    func save(in context: NSManagedObjectContext) throws -> CDBill {
        let bill = CDBill(context: context)
        bill.id = UUID()
        bill.merchant = merchant.trimmingCharacters(in: .whitespaces)
        bill.date = date
        bill.group = group
        bill.payer = payerID.flatMap { group.member(with: $0) }
        bill.splitModeRaw = mode.rawValue
        bill.serviceCharge = NSDecimalNumber(decimal: serviceCharge)
        bill.tax = NSDecimalNumber(decimal: tax)
        bill.subtotal = NSDecimalNumber(decimal: itemsSubtotal)
        bill.total = NSDecimalNumber(decimal: total)
        bill.receiptImage = receiptImage
        bill.featurePrint = featurePrint
        bill.rawOCRText = rawOCRText

        for (index, draft) in items.enumerated() {
            let item = CDItem(context: context)
            item.id = UUID()
            item.name = draft.name.isEmpty ? "Item" : draft.name
            item.amount = NSDecimalNumber(decimal: draft.amount)
            item.categoryRaw = draft.category.rawValue
            item.wasEdited = false
            item.position = Int16(index)
            item.bill = bill

            for assignee in draft.assignees {
                guard let member = group.member(with: assignee) else { continue }
                let share = CDItemShare(context: context)
                share.id = UUID()
                share.weight = 1
                share.item = item
                share.member = member
            }
        }

        try context.save()
        return bill
    }
    
    /// Fills the draft from a scanned receipt. Everything stays editable,
    /// so a misread line never blocks the user.
    func apply(_ parsed: ReceiptParser.ParsedReceipt, scan: ReceiptScanner.ScanResult) {
        if let merchant = parsed.merchant, !merchant.isEmpty {
            self.merchant = merchant
        }
        items = parsed.items.map { parsedItem in
            DraftItem(name: parsedItem.name,
                      amount: parsedItem.amount,
                      category: CategoryClassifier.category(for: parsedItem.name))
        }
        serviceCharge = parsed.serviceCharge ?? 0
        tax = parsed.tax ?? 0
        scannedTotal = parsed.total
        reconciles = parsed.reconciles
        receiptImage = scan.correctedImage.jpegData(compressionQuality: 0.7)
        featurePrint = scan.featurePrint
        rawOCRText = scan.rawText
    }
}
