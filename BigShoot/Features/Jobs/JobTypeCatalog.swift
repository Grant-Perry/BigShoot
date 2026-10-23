import Foundation

@MainActor
@Observable
final class JobTypeCatalog {
    static let commercial = "Commercial"
    static let weddings = "Weddings"
    static let builtIn = [commercial, weddings]

    private static let storageKey = "BigShoot.jobTypes"
    private let defaults: UserDefaults
    private(set) var names: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.storageKey) ?? []
        names = Self.ordered(stored)
    }

    /// Returns the name to select. Blank input is ignored. A case-insensitive match keeps the existing spelling.
    @discardableResult
    func add(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = names.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        names.append(trimmed)
        defaults.set(names, forKey: Self.storageKey)
        return trimmed
    }

    private static func ordered(_ stored: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        func append(_ name: String) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            result.append(trimmed)
        }
        builtIn.forEach(append)
        stored.forEach(append)
        return result
    }
}
