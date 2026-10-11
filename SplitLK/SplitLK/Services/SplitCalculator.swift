import Foundation

/// Works out what each member owes for a single bill.
enum SplitCalculator {

    /// Returns member id to the amount they owe. The values always sum to the bill total.
    static func shares(for input: SplitInput) throws -> [UUID: Decimal] {
        guard !input.participants.isEmpty else { throw SplitError.noParticipants }

        switch input.mode {
        case .equally:
            return splitEqually(input)
        case .byItem:
            return splitByItem(input)
        case .custom:
            return try splitCustom(input)
        }
    }

    // MARK: - Equally

    private static func splitEqually(_ input: SplitInput) -> [UUID: Decimal] {
        let parts = Money.divide(input.total, into: input.participants.count)
        return Dictionary(uniqueKeysWithValues: zip(input.participants, parts))
    }

    // MARK: - By item

    /// Each item is divided among the people assigned to it. Unassigned items fall
    /// back to an equal split across everyone. Service charge and tax are then
    /// allocated in proportion to what each person consumed, not split flat —
    /// a 10% charge should cost more for the person who ordered more.
    private static func splitByItem(_ input: SplitInput) -> [UUID: Decimal] {
        var consumed: [UUID: Decimal] = [:]
        for id in input.participants { consumed[id] = 0 }

        for item in input.items {
            let targets: [UUID]
            let weights: [Decimal]

            if item.isAssigned {
                targets = Array(item.assignments.keys)
                weights = targets.map { item.assignments[$0] ?? 1 }
            } else {
                targets = input.participants
                weights = targets.map { _ in 1 }
            }

            let parts = Money.allocate(item.amount, proportionalTo: weights)
            for (target, part) in zip(targets, parts) {
                consumed[target, default: 0] += part
            }
        }

        let extras = input.serviceCharge + input.tax
        guard extras != 0 else { return consumed }

        let order = input.participants
        let weights = order.map { consumed[$0] ?? 0 }
        let extraParts = Money.allocate(extras, proportionalTo: weights)

        var result = consumed
        for (id, extra) in zip(order, extraParts) {
            result[id, default: 0] += extra
        }
        return result
    }

    // MARK: - Custom

    private static func splitCustom(_ input: SplitInput) throws -> [UUID: Decimal] {
        let sum = input.customAmounts.values.reduce(0, +)
        guard Money.round(sum) == Money.round(input.total) else {
            throw SplitError.customAmountsDoNotMatchTotal(expected: input.total, got: sum)
        }
        var result: [UUID: Decimal] = [:]
        for id in input.participants {
            result[id] = input.customAmounts[id] ?? 0
        }
        return result
    }
}
