import Foundation

struct BackupPreferences: Codable, Sendable, Equatable {
    var bannerText: String
    var jobTypes: [String]
    var paymentMethods: [String]
}

enum BackupPreferenceStore {
    static func capture(_ defaults: UserDefaults) -> BackupPreferences {
        BackupPreferences(
            bannerText: defaults.string(forKey: StudioBanner.key) ?? "",
            jobTypes: defaults.stringArray(forKey: JobTypeCatalog.storageKey) ?? [],
            paymentMethods: defaults.stringArray(forKey: PaymentMethodCatalog.storageKey) ?? []
        )
    }

    static func replace(_ preferences: BackupPreferences, in defaults: UserDefaults) {
        defaults.set(preferences.bannerText, forKey: StudioBanner.key)
        defaults.set(preferences.jobTypes, forKey: JobTypeCatalog.storageKey)
        defaults.set(preferences.paymentMethods, forKey: PaymentMethodCatalog.storageKey)
    }

    static func merge(_ preferences: BackupPreferences, in defaults: UserDefaults) {
        defaults.set(preferences.bannerText, forKey: StudioBanner.key)
        defaults.set(union(defaults.stringArray(forKey: JobTypeCatalog.storageKey) ?? [], preferences.jobTypes), forKey: JobTypeCatalog.storageKey)
        defaults.set(
            union(defaults.stringArray(forKey: PaymentMethodCatalog.storageKey) ?? [], preferences.paymentMethods),
            forKey: PaymentMethodCatalog.storageKey
        )
    }

    private static func union(_ current: [String], _ incoming: [String]) -> [String] {
        var seen = Set(current.map { $0.lowercased() })
        var result = current
        for name in incoming {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}
