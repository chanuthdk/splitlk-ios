import Foundation
import AppIntents
import CoreData

/// A group exposed to Siri and Shortcuts, so "log Rs 1500 fuel" can offer
/// the user's real groups as options rather than taking a typed string.
struct GroupEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Group")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var defaultQuery = GroupEntityQuery()
}

struct GroupEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [GroupEntity] {
        try await MainActor.run {
            try allGroups().filter { identifiers.contains($0.id) }
        }
    }

    func suggestedEntities() async throws -> [GroupEntity] {
        try await MainActor.run { try allGroups() }
    }

    /// The view context belongs to the main thread, so every fetch here is
    /// hopped onto it rather than reaching across threads from Shortcuts.
    @MainActor
    private func allGroups() throws -> [GroupEntity] {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<CDGroup>(entityName: "CDGroup")
        request.predicate = NSPredicate(format: "isArchived == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        return try context.fetch(request).map {
            GroupEntity(id: $0.groupID, name: $0.displayName)
        }
    }
}

/// "Log Rs 1500 fuel to Galle Trip"
///
/// Writes into the same Core Data store the app uses, so an expense logged
/// through Siri appears in the group immediately and is split equally until
/// the user opens the app and assigns it.
struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log an Expense"
    static var description = IntentDescription(
        "Adds a quick expense to one of your SplitLK groups, split equally."
    )

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Description")
    var note: String

    @Parameter(title: "Group")
    var group: GroupEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) for \(\.$note) to \(\.$group)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.container.viewContext

        let request = NSFetchRequest<CDGroup>(entityName: "CDGroup")
        request.predicate = NSPredicate(format: "id == %@", group.id as CVarArg)
        request.fetchLimit = 1

        guard let target = try context.fetch(request).first else {
            throw IntentError.groupNotFound
        }
        guard amount > 0 else {
            throw IntentError.invalidAmount
        }

        let value = Money.round(Decimal(amount))

        let bill = CDBill(context: context)
        bill.id = UUID()
        bill.merchant = note.isEmpty ? "Quick expense" : note
        bill.date = Date()
        bill.group = target
        bill.payer = target.me ?? target.memberList.first
        // Siri has no way to ask who consumed what, so an equal split is the
        // honest default; the user can refine it in the app.
        bill.splitModeRaw = SplitMode.equally.rawValue
        bill.serviceCharge = 0
        bill.tax = 0
        bill.subtotal = NSDecimalNumber(decimal: value)
        bill.total = NSDecimalNumber(decimal: value)

        let item = CDItem(context: context)
        item.id = UUID()
        item.name = bill.merchant ?? "Quick expense"
        item.amount = NSDecimalNumber(decimal: value)
        item.categoryRaw = SpendingCategory.other.rawValue
        item.wasEdited = false
        item.position = 0
        item.bill = bill

        try context.save()

        return .result(dialog: "Added \(Money.format(value)) to \(target.displayName).")
    }
}

/// "What do I owe?"
struct CheckBalanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Check My Balance"
    static var description = IntentDescription(
        "Tells you what you're owed and what you owe across your groups."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.container.viewContext

        let request = NSFetchRequest<CDGroup>(entityName: "CDGroup")
        request.predicate = NSPredicate(format: "isArchived == NO")

        let groups = try context.fetch(request)
        var owedToMe: Decimal = 0
        var iOwe: Decimal = 0

        for group in groups {
            let balance = BalanceService.myBalance(in: group)
            if balance > 0 { owedToMe += balance }
            if balance < 0 { iOwe += abs(balance) }
        }

        if owedToMe == 0 && iOwe == 0 {
            return .result(dialog: "You're all settled up.")
        }
        if iOwe == 0 {
            return .result(dialog: "You're owed \(Money.format(owedToMe)).")
        }
        if owedToMe == 0 {
            return .result(dialog: "You owe \(Money.format(iOwe)).")
        }
        return .result(dialog: "You're owed \(Money.format(owedToMe)) and you owe \(Money.format(iOwe)).")
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case groupNotFound
    case invalidAmount

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .groupNotFound: return "That group no longer exists."
        case .invalidAmount: return "The amount needs to be more than zero."
        }
    }
}

/// Registers both intents with Shortcuts and Spotlight on first launch.
struct SplitLKShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckBalanceIntent(),
            phrases: [
                "What do I owe in \(.applicationName)",
                "Check my \(.applicationName) balance"
            ],
            shortTitle: "Check Balance",
            systemImageName: "equal.circle"
        )
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add a \(.applicationName) expense"
            ],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle"
        )
    }
}
