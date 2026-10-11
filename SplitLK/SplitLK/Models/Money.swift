import Foundation

enum Money {
    /// Rounds to 2 decimal places using bankers-free, half-up rounding.
    static func round(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    /// Splits an amount into `count` parts that sum exactly to the original.
    /// Remainder cents are distributed one at a time to the earliest parts.
    static func divide(_ amount: Decimal, into count: Int) -> [Decimal] {
        guard count > 0 else { return [] }

        let cents = NSDecimalNumber(decimal: round(amount) * 100).intValue
        let base = cents / count
        let remainder = abs(cents % count)
        let step = cents < 0 ? -1 : 1

        return (0..<count).map { index in
            let value = base + (index < remainder ? step : 0)
            return Decimal(value) / 100
        }
    }

    /// Allocates an amount across weights so the parts sum exactly to the original.
    /// Uses the largest-remainder method: everyone gets their floor share, then
    /// leftover cents go to whoever was rounded down hardest.
    static func allocate(_ amount: Decimal, proportionalTo weights: [Decimal]) -> [Decimal] {
        let totalWeight = weights.reduce(0, +)
        guard !weights.isEmpty else { return [] }
        guard totalWeight > 0 else { return divide(amount, into: weights.count) }

        let totalCents = NSDecimalNumber(decimal: round(amount) * 100).intValue

        var exact: [Double] = []
        for weight in weights {
            let ratio = NSDecimalNumber(decimal: weight / totalWeight).doubleValue
            exact.append(Double(totalCents) * ratio)
        }

        var cents = exact.map { Int($0.rounded(.down)) }
        var remaining = totalCents - cents.reduce(0, +)

        let order = exact.indices.sorted {
            (exact[$0] - Double(cents[$0])) > (exact[$1] - Double(cents[$1]))
        }

        var index = 0
        while remaining > 0 && !order.isEmpty {
            cents[order[index % order.count]] += 1
            remaining -= 1
            index += 1
        }

        return cents.map { Decimal($0) / 100 }
    }
    
    static func format(_ amount: Decimal, currencyCode: String = "LKR") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.currencySymbol = currencyCode == "LKR" ? "Rs " : formatter.currencySymbol
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }
}
