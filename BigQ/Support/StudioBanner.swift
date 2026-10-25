import Foundation

/// The words at the top of the books. Stored in user defaults; blank means the fallback.
enum StudioBanner {
    static let key = "BigQ.bannerText"
    static let fallback = "BigQ"

    static func resolved(_ stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
