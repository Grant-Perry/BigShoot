import Foundation

/// Turns a typed tax rate into a fraction and a dollar amount.
///
/// `6.6` and `6.6%` mean 6.6 percent. `0.066` and `.066` mean the same rate written as a fraction.
nonisolated enum TaxRateInput {
    static func fraction(from text: String) -> Decimal? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return 0 }
        let markedPercent = raw.contains("%")
        raw = raw.replacingOccurrences(of: "%", with: "")
        raw = raw.replacingOccurrences(of: ",", with: "")
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let clamped = value < 0 ? Decimal.zero : value
        if markedPercent || !isWrittenAsFraction(raw, value: clamped) {
            return clamped / 100
        }
        return clamped
    }

    /// Percent points for the field and menus, such as "6.6" for a 0.066 rate.
    static func percentText(for fraction: Decimal) -> String {
        let points = fraction * 100
        return points.formatted(
            .number.precision(.fractionLength(0...4)).locale(Locale(identifier: "en_US_POSIX"))
        )
    }

    static func amount(taxableSubtotal: Decimal, rate: Decimal) -> Decimal {
        var result = Decimal()
        var value = taxableSubtotal * rate
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }

    /// A leading decimal at or under 1 is already a fraction. Everything else is percent points.
    private static func isWrittenAsFraction(_ raw: String, value: Decimal) -> Bool {
        guard value <= 1 else { return false }
        return raw.hasPrefix(".") || raw.hasPrefix("0.")
    }
}
