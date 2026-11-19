import Foundation
import SwiftData

/// A reusable quote letter. Agreement variables such as `[Client Name]`, `[Quote Number]`, and `[Retainer]`, plus `[Pay Link]` and `[Letterhead]`, fill in per quote.
@Model
final class EmailTemplate {
    var name: String = ""
    var subject: String = ""
    var body: String = ""
    var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)

    init(name: String, subject: String, body: String) {
        self.name = name
        self.subject = subject
        self.body = body
        self.createdAt = .now
        self.updatedAt = .now
    }
}
