import Foundation

/// Built-in methods plus custom ones remembered on this Mac. Other is the add action, not a type.
@MainActor
@Observable
final class PaymentMethodCatalog {
    enum Add: Equatable {
        case added(String)
        case duplicate(String)
        case empty
    }

    private static let storageKey = "BigQ.paymentMethods"
    private static let builtInKeys = [
        PaymentMethod.card.rawValue,
        PaymentMethod.check.rawValue,
        PaymentMethod.manual.rawValue,
    ]

    private let defaults: UserDefaults
    private(set) var names: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = Self.ordered(stored: defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    var titles: [String] {
        names.map(PaymentMethod.displayTitle(for:))
    }

    /// Blank input is ignored. A case-insensitive match of a built-in, custom, or Other name is refused.
    func add(_ raw: String) -> Add {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if let reserved = Self.reservedTitle(matching: trimmed) {
            return .duplicate(reserved)
        }
        if let existing = names.first(where: { Self.matches($0, trimmed) }) {
            return .duplicate(PaymentMethod.displayTitle(for: existing))
        }
        names = Self.ordered(stored: customNames + [trimmed])
        defaults.set(customNames, forKey: Self.storageKey)
        return .added(trimmed)
    }

    private var customNames: [String] {
        names.filter { !Self.isBuiltIn($0) }
    }

    private static func ordered(stored: [String]) -> [String] {
        var seen = Set<String>()
        var custom: [String] = []
        for name in stored {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if reservedTitle(matching: trimmed) != nil { continue }
            if isBuiltIn(trimmed) { continue }
            guard seen.insert(trimmed.lowercased()).inserted else { continue }
            custom.append(trimmed)
        }
        return (builtInKeys + custom).sorted {
            PaymentMethod.displayTitle(for: $0).localizedStandardCompare(PaymentMethod.displayTitle(for: $1)) == .orderedAscending
        }
    }

    private static func isBuiltIn(_ key: String) -> Bool {
        builtInKeys.contains { matches($0, key) }
    }

    private static func matches(_ key: String, _ typed: String) -> Bool {
        key.caseInsensitiveCompare(typed) == .orderedSame
            || PaymentMethod.displayTitle(for: key).caseInsensitiveCompare(typed) == .orderedSame
    }

    private static func reservedTitle(matching typed: String) -> String? {
        let other = PaymentMethod.other
        if typed.caseInsensitiveCompare(other.title) == .orderedSame
            || typed.caseInsensitiveCompare(other.rawValue) == .orderedSame {
            return other.title
        }
        return nil
    }
}
