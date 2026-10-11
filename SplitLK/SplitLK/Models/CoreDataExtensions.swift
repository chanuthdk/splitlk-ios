import Foundation
import CoreData

extension CDGroup {
    var groupID: UUID { id ?? UUID() }
    var displayName: String { name ?? "Untitled Group" }
    var currency: String { currencyCode ?? "LKR" }
    var memberList: [CDMember] {
        (members as? Set<CDMember> ?? []).sorted { $0.displayName < $1.displayName }
    }
    var billList: [CDBill] {
        (bills as? Set<CDBill> ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    var settlementList: [CDSettlement] {
        Array(settlements as? Set<CDSettlement> ?? [])
    }
}

extension CDMember {
    var memberID: UUID { id ?? UUID() }
    var displayName: String { name ?? "Unknown" }
    var initials: String {
        displayName.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

extension CDBill {
    var billID: UUID { id ?? UUID() }
    var displayMerchant: String { merchant ?? "Bill" }
    var totalAmount: Decimal { total?.decimalValue ?? 0 }
    var serviceChargeAmount: Decimal { serviceCharge?.decimalValue ?? 0 }
    var taxAmount: Decimal { tax?.decimalValue ?? 0 }
    var splitMode: SplitMode { SplitMode(rawValue: splitModeRaw ?? "") ?? .equally }
    var itemList: [CDItem] {
        (items as? Set<CDItem> ?? []).sorted { $0.displayName < $1.displayName }
    }
    var customShareList: [CDBillShare] {
        Array(customShares as? Set<CDBillShare> ?? [])
    }
}

extension CDItem {
    var itemID: UUID { id ?? UUID() }
    var displayName: String { name ?? "Item" }
    var itemAmount: Decimal { amount?.decimalValue ?? 0 }
    var category: SpendingCategory { SpendingCategory(rawValue: categoryRaw ?? "") ?? .other }
    var shareList: [CDItemShare] {
        Array(shares as? Set<CDItemShare> ?? [])
    }
}

extension CDBillShare {
    var shareAmount: Decimal { amount?.decimalValue ?? 0 }
}

extension CDSettlement {
    var settlementAmount: Decimal { amount?.decimalValue ?? 0 }
}

extension CDGroup {
    func member(with id: UUID) -> CDMember? {
        memberList.first { $0.memberID == id }
    }

    var me: CDMember? { memberList.first { $0.isMe } }
}
