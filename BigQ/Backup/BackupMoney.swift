import Foundation

enum BackupMoney {
    static func text(_ value: Decimal) -> String {
        var value = value
        return NSDecimalString(&value, nil)
    }

    static func decimal(_ text: String) throws -> Decimal {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw BackupError.unreadable
        }
        return value
    }

    static func optional(_ text: String?) throws -> Decimal? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try decimal(trimmed)
    }
}
