import Foundation
import CoreData

/// The wire format used to sync a group through Firestore.
///
/// These are deliberately separate from the Core Data classes: the stored
/// schema and the local model can then change independently, and the mapping
/// between them stays in one readable place rather than being spread across
/// the networking code.
///
/// Money is carried as a string rather than a number. Firestore stores
/// numbers as IEEE 754 doubles, which cannot represent values such as 0.1
/// exactly, so round-tripping an amount through a double would drift the
/// balances a little on every sync. A string round-trips a Decimal exactly.
struct GroupDTO: Codable {
    var id: String
    var name: String
    var currencyCode: String
    var createdAt: Date
    var inviteCode: String
    var updatedAt: Date
    /// Firebase Auth uids allowed to read and write this group. Used by the
    /// Firestore security rules, not by the app's own logic.
    var memberUids: [String]
    /// Optional because documents written before the group picker existed
    /// have neither field, and a non-optional would fail to decode them.
    var colorHex: String?
    var iconName: String?
}

struct MemberDTO: Codable {
    var id: String
    var name: String
    var colorHex: String
    /// The Firebase uid of the device that claims to be this member, if any.
    /// Lets each phone work out which member represents its own user.
    var linkedUid: String?
}

struct ItemDTO: Codable {
    var id: String
    var name: String
    var amount: String
    var categoryRaw: String
    var position: Int
    var assigneeIds: [String]
}

struct BillDTO: Codable {
    var id: String
    var merchant: String
    var date: Date
    var subtotal: String
    var serviceCharge: String
    var tax: String
    var total: String
    var splitModeRaw: String
    var payerId: String?
    var items: [ItemDTO]
}

struct SettlementDTO: Codable {
    var id: String
    var amount: String
    var date: Date
    var fromId: String?
    var toId: String?
    var note: String?
}

/// Everything needed to reconstruct one group on another device.
struct GroupBundle {
    var group: GroupDTO
    var members: [MemberDTO]
    var bills: [BillDTO]
    var settlements: [SettlementDTO]
}

// MARK: - Core Data to DTO

enum SyncMapper {

    static func amountString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: Money.round(value)).stringValue
    }

    static func decimal(_ string: String) -> Decimal {
        Decimal(string: string) ?? 0
    }

    static func bundle(from group: CDGroup, memberUids: [String]) -> GroupBundle {
        let groupDTO = GroupDTO(
            id: group.groupID.uuidString,
            name: group.displayName,
            currencyCode: group.currency,
            createdAt: group.createdAt ?? Date(),
            inviteCode: group.inviteCode ?? "",
            updatedAt: Date(),
            memberUids: memberUids,
            colorHex: group.displayColorHex,
            iconName: group.displayIconName
        )

        let members = group.memberList.map { member in
            MemberDTO(id: member.memberID.uuidString,
                      name: member.displayName,
                      colorHex: member.colorHex ?? GroupStyle.defaultColorHex,
                      linkedUid: member.linkedUid)
        }

        let bills = group.billList.map { bill in
            BillDTO(
                id: bill.billID.uuidString,
                merchant: bill.displayMerchant,
                date: bill.date ?? Date(),
                subtotal: amountString(bill.subtotal?.decimalValue ?? 0),
                serviceCharge: amountString(bill.serviceChargeAmount),
                tax: amountString(bill.taxAmount),
                total: amountString(bill.totalAmount),
                splitModeRaw: bill.splitModeRaw ?? SplitMode.equally.rawValue,
                payerId: bill.payer?.memberID.uuidString,
                items: bill.itemList.map { item in
                    ItemDTO(id: item.itemID.uuidString,
                            name: item.displayName,
                            amount: amountString(item.itemAmount),
                            categoryRaw: item.categoryRaw ?? SpendingCategory.other.rawValue,
                            position: Int(item.position),
                            assigneeIds: item.shareList.compactMap { $0.member?.memberID.uuidString })
                }
            )
        }

        let settlements = group.settlementList.map { settlement in
            SettlementDTO(id: (settlement.id ?? UUID()).uuidString,
                          amount: amountString(settlement.settlementAmount),
                          date: settlement.date ?? Date(),
                          fromId: settlement.fromMember?.memberID.uuidString,
                          toId: settlement.toMember?.memberID.uuidString,
                          note: settlement.note)
        }

        return GroupBundle(group: groupDTO,
                           members: members,
                           bills: bills,
                           settlements: settlements)
    }

    // MARK: - DTO to Core Data

    /// Writes a downloaded bundle into Core Data, matching on the ids that
    /// came from the server so a second sync updates rather than duplicates.
    ///
    /// The remote copy wins on conflict. That is the honest behaviour for a
    /// shared ledger: two people editing the same bill offline is rare, and
    /// silently keeping the local version would make the group's totals
    /// disagree between phones with no way to notice.
    @discardableResult
    static func apply(_ bundle: GroupBundle,
                      in context: NSManagedObjectContext) throws -> CDGroup {
        guard let groupID = UUID(uuidString: bundle.group.id) else {
            throw SyncError.malformedPayload
        }

        let group = try findOrCreateGroup(id: groupID, in: context)
        group.name = bundle.group.name
        group.currencyCode = bundle.group.currencyCode
        group.createdAt = bundle.group.createdAt
        group.inviteCode = bundle.group.inviteCode
        group.isArchived = false
        // Falls back rather than writing nil, so a group shared from a device
        // on an older build still gets a colour and an icon here.
        group.colorHex = bundle.group.colorHex ?? GroupStyle.fallbackColorHex(for: bundle.group.name)
        group.iconName = bundle.group.iconName ?? GroupStyle.defaultIconName

        var membersByID: [String: CDMember] = [:]
        for dto in bundle.members {
            guard let id = UUID(uuidString: dto.id) else { continue }

            let member: CDMember
            if let found = existing(CDMember.self, id: id, in: context) {
                member = found
            } else {
                member = CDMember(context: context)
                // Downloaded members are other people by default. Which one
                // represents this device is decided separately, when the user
                // claims their seat, so it must not be left unset here.
                member.isMe = false
            }

            member.id = id
            member.name = dto.name
            member.colorHex = dto.colorHex
            member.linkedUid = dto.linkedUid
            member.group = group
            membersByID[dto.id] = member
        }

        for dto in bundle.bills {
            guard let id = UUID(uuidString: dto.id) else { continue }
            let bill = existing(CDBill.self, id: id, in: context) ?? CDBill(context: context)
            bill.id = id
            bill.merchant = dto.merchant
            bill.date = dto.date
            bill.subtotal = NSDecimalNumber(decimal: decimal(dto.subtotal))
            bill.serviceCharge = NSDecimalNumber(decimal: decimal(dto.serviceCharge))
            bill.tax = NSDecimalNumber(decimal: decimal(dto.tax))
            bill.total = NSDecimalNumber(decimal: decimal(dto.total))
            bill.splitModeRaw = dto.splitModeRaw
            bill.payer = dto.payerId.flatMap { membersByID[$0] }
            bill.group = group

            // Items are replaced wholesale rather than merged: a bill's lines
            // are only ever edited together, and rebuilding them avoids having
            // to reconcile deletions item by item.
            for old in bill.itemList { context.delete(old) }

            for itemDTO in dto.items {
                let item = CDItem(context: context)
                item.id = UUID(uuidString: itemDTO.id) ?? UUID()
                item.name = itemDTO.name
                item.amount = NSDecimalNumber(decimal: decimal(itemDTO.amount))
                item.categoryRaw = itemDTO.categoryRaw
                item.position = Int16(itemDTO.position)
                item.wasEdited = false
                item.bill = bill

                for assigneeID in itemDTO.assigneeIds {
                    guard let member = membersByID[assigneeID] else { continue }
                    let share = CDItemShare(context: context)
                    share.id = UUID()
                    share.weight = 1
                    share.item = item
                    share.member = member
                }
            }
        }

        for dto in bundle.settlements {
            guard let id = UUID(uuidString: dto.id) else { continue }
            let settlement = existing(CDSettlement.self, id: id, in: context)
                ?? CDSettlement(context: context)
            settlement.id = id
            settlement.amount = NSDecimalNumber(decimal: decimal(dto.amount))
            settlement.date = dto.date
            settlement.note = dto.note
            settlement.fromMember = dto.fromId.flatMap { membersByID[$0] }
            settlement.toMember = dto.toId.flatMap { membersByID[$0] }
            settlement.group = group
        }

        try context.save()
        return group
    }

    // MARK: - Lookups

    private static func findOrCreateGroup(id: UUID,
                                          in context: NSManagedObjectContext) throws -> CDGroup {
        if let found = existing(CDGroup.self, id: id, in: context) { return found }
        let group = CDGroup(context: context)
        group.id = id
        return group
    }

    private static func existing<T: NSManagedObject>(_ type: T.Type,
                                                     id: UUID,
                                                     in context: NSManagedObjectContext) -> T? {
        let name = String(describing: type)
        let request = NSFetchRequest<T>(entityName: name)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}

enum SyncError: Error, LocalizedError {
    case notSignedIn
    case groupNotFound
    case malformedPayload
    case alreadyJoined

    var errorDescription: String? {
        switch self {
        case .notSignedIn:      return "Couldn't reach the sync service. Check your connection and try again."
        case .groupNotFound:    return "No group matches that invite code."
        case .malformedPayload: return "That group's data couldn't be read."
        case .alreadyJoined:    return "You're already a member of that group."
        }
    }
}

extension Error {
    /// Core Data reports a failed save with several problems as a single
    /// "Multiple validation errors occurred", hiding the detail in userInfo.
    /// This unwraps it into something that names the entity and attribute,
    /// which is the difference between a usable bug report and a shrug.
    var detailedDescription: String {
        let error = self as NSError

        let nested = (error.userInfo[NSDetailedErrorsKey] as? [NSError]) ?? [error]

        let parts: [String] = nested.map { item in
            let entity = (item.userInfo[NSValidationObjectErrorKey] as? NSManagedObject)?
                .entity.name ?? "object"
            if let key = item.userInfo[NSValidationKeyErrorKey] as? String {
                return "\(entity).\(key): \(item.localizedDescription)"
            }
            return "\(entity): \(item.localizedDescription)"
        }

        return parts.joined(separator: "\n")
    }
}
