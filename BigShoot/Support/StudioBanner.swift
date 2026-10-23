import Foundation

/// The words at the top of the books. Stored in user defaults; blank means the fallback.
enum StudioBanner {
    static let key = "BigShoot.bannerText"
    static let fallback = "BigShoot"

    static func resolved(_ stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
