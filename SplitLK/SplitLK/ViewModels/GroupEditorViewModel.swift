import Foundation
import CoreData
import SwiftUI

/// Holds a group while it is being created, before anything is written
/// to Core Data. Keeping the draft out of the store means a cancelled
/// sheet leaves nothing behind to clean up.
@Observable
final class GroupEditorViewModel {

    struct DraftMember: Identifiable {
        let id = UUID()
        var name: String
        var colorHex: String
        var isMe: Bool
    }

    /// Distinct hues so members stay tellable apart in avatars and charts.
    static let palette = ["4F46E5", "16A34A", "D97706", "DC2626",
                          "0891B2", "7C3AED", "DB2777", "65A30D"]

    var name: String = ""
    var currencyCode: String = "LKR"
    var members: [DraftMember]
    var newMemberName: String = ""
    var colorHex: String = GroupStyle.defaultColorHex
    var iconName: String = GroupStyle.defaultIconName

    /// Short, human-readable code other members type to join this group.
    /// Ambiguous characters (0/O, 1/I) are left out so it survives being
    /// read aloud or copied by hand.
    let inviteCode: String

    init(myName: String = "Me") {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = (0..<8).map { _ in String(alphabet.randomElement() ?? "A") }.joined()
        self.inviteCode = "\(code.prefix(4))-\(code.suffix(4))"
        self.members = [DraftMember(name: myName,
                                    colorHex: Self.palette[0],
                                    isMe: true)]
    }

    // MARK: - Validation

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var canSave: Bool {
        !trimmedName.isEmpty && members.count >= 2
    }

    var validationHint: String? {
        if trimmedName.isEmpty { return "Give the group a name." }
        if members.count < 2 { return "Add at least one other person to split with." }
        return nil
    }

    // MARK: - Editing

    func addMember() {
        let trimmed = newMemberName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Names are how members are told apart in the UI, so duplicates
        // would make the assignment screen ambiguous.
        guard !members.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newMemberName = ""
            return
        }

        let colour = Self.palette[members.count % Self.palette.count]
        members.append(DraftMember(name: trimmed, colorHex: colour, isMe: false))
        newMemberName = ""
    }

    func removeMembers(at offsets: IndexSet) {
        // The current user is always a participant and cannot be removed.
        let removable = offsets.filter { !members[$0].isMe }
        members.remove(atOffsets: IndexSet(removable))
    }

    // MARK: - Saving

    @discardableResult
    func save(in context: NSManagedObjectContext) throws -> CDGroup {
        let group = CDGroup(context: context)
        group.id = UUID()
        group.name = trimmedName
        group.currencyCode = currencyCode
        group.createdAt = Date()
        group.isArchived = false
        group.inviteCode = inviteCode
        group.colorHex = colorHex
        group.iconName = iconName

        for draft in members {
            let member = CDMember(context: context)
            member.id = UUID()
            member.name = draft.name
            member.colorHex = draft.colorHex
            member.isMe = draft.isMe
            member.group = group
        }

        try context.save()
        return group
    }
}
