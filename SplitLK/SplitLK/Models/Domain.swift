import Foundation

/// One line on a receipt, plus who is responsible for it.
struct SplitItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var amount: Decimal
    /// Member id to weight. Equal weights mean an even share of this item.
    var assignments: [UUID: Decimal]

    init(id: UUID = UUID(), name: String, amount: Decimal, assignments: [UUID: Decimal] = [:]) {
        self.id = id
        self.name = name
        self.amount = amount
        self.assignments = assignments
    }

    var isAssigned: Bool { !assignments.isEmpty }
}

/// Everything the calculator needs to split one bill.
struct SplitInput {
    var participants: [UUID]
    var items: [SplitItem]
    var serviceCharge: Decimal
    var tax: Decimal
    var mode: SplitMode
    /// Only used when mode is .custom
    var customAmounts: [UUID: Decimal]

    init(participants: [UUID],
         items: [SplitItem] = [],
         serviceCharge: Decimal = 0,
         tax: Decimal = 0,
         mode: SplitMode = .equally,
         customAmounts: [UUID: Decimal] = [:]) {
        self.participants = participants
        self.items = items
        self.serviceCharge = serviceCharge
        self.tax = tax
        self.mode = mode
        self.customAmounts = customAmounts
    }

    var itemsSubtotal: Decimal { items.reduce(0) { $0 + $1.amount } }
    var total: Decimal { itemsSubtotal + serviceCharge + tax }
}

/// One payment that moves money from one member to another.
struct Transfer: Equatable {
    let from: UUID
    let to: UUID
    let amount: Decimal
}

enum SplitError: Error, Equatable {
    case noParticipants
    case customAmountsDoNotMatchTotal(expected: Decimal, got: Decimal)
}
