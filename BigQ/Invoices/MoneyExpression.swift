import Foundation

/// A price typed into a field. A leading `=` or `+ − × ÷` runs the math.
/// `=4750*2` becomes 9500.00. Plain numbers pass through.
nonisolated enum MoneyExpression {
    /// Cents, or nil when the text is not a finished price.
    static func resolve(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        var parser = Parser(normalized(trimmed))
        guard let value = parser.parse() else { return nil }
        return cents(value)
    }

    /// Plain numbers update as you type. A formula waits until it has an operator,
    /// so `=4` does not replace the price while `=4750*2` is still being entered.
    static func appliesWhileTyping(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let expression = normalized(trimmed)
        let arithmetic = hasOperator(expression)
        if trimmed.hasPrefix("="), !arithmetic { return false }
        return resolve(trimmed) != nil
    }

    private static func normalized(_ text: String) -> String {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("=") {
            raw.removeFirst()
        }
        return raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "X", with: "*")
    }

    private static func hasOperator(_ expression: String) -> Bool {
        var rest = expression[...]
        if rest.first == "+" || rest.first == "-" {
            rest = rest.dropFirst()
        }
        return rest.contains { "+-*/()".contains($0) }
    }

    private static func cents(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var source = value
        NSDecimalRound(&result, &source, 2, .plain)
        return result
    }

    private struct Parser {
        private let characters: [Character]
        private var index = 0

        init(_ source: String) {
            characters = Array(source)
        }

        mutating func parse() -> Decimal? {
            skipSpace()
            guard let value = parseExpression() else { return nil }
            skipSpace()
            guard index == characters.count else { return nil }
            return value
        }

        private mutating func parseExpression() -> Decimal? {
            guard var left = parseTerm() else { return nil }
            while true {
                skipSpace()
                if consume("+") {
                    guard let right = parseTerm() else { return nil }
                    left += right
                } else if consume("-") {
                    guard let right = parseTerm() else { return nil }
                    left -= right
                } else {
                    return left
                }
            }
        }

        private mutating func parseTerm() -> Decimal? {
            guard var left = parseUnary() else { return nil }
            while true {
                skipSpace()
                if consume("*") {
                    guard let right = parseUnary() else { return nil }
                    left *= right
                } else if consume("/") {
                    guard let right = parseUnary(), right != 0 else { return nil }
                    left /= right
                } else {
                    return left
                }
            }
        }

        private mutating func parseUnary() -> Decimal? {
            skipSpace()
            if consume("-") {
                guard let value = parseUnary() else { return nil }
                return -value
            }
            if consume("+") {
                return parseUnary()
            }
            return parsePrimary()
        }

        private mutating func parsePrimary() -> Decimal? {
            skipSpace()
            if consume("(") {
                guard let value = parseExpression() else { return nil }
                skipSpace()
                guard consume(")") else { return nil }
                return value
            }
            return parseNumber()
        }

        private mutating func parseNumber() -> Decimal? {
            skipSpace()
            let start = index
            var sawDigit = false
            var sawDot = false
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    sawDigit = true
                    index += 1
                } else if character == ".", !sawDot {
                    sawDot = true
                    index += 1
                } else {
                    break
                }
            }
            guard sawDigit else { return nil }
            var raw = String(characters[start..<index])
            if raw.hasSuffix(".") {
                raw.removeLast()
            }
            return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
        }

        private mutating func consume(_ character: Character) -> Bool {
            guard index < characters.count, characters[index] == character else { return false }
            index += 1
            return true
        }

        private mutating func skipSpace() {
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
        }
    }
}
