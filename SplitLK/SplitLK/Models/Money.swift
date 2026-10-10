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

    static func format(_ amount: Decimal, currencyCode: String = "LKR") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.currencySymbol = currencyCode == "LKR" ? "Rs " : formatter.currencySymbol
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }
}
