import Foundation
import SwiftData

/// One studio under this roof. Invoices keep the studio that issued them.
@Model
final class StudioBrand {
    static let defaultName = "Grant & Deb Photographers"

    var name: String
    var email: String
    var phone: String
    var address: String
    var isPrimary: Bool
    var archived: Bool
    var createdAt: Date
    /// Cropped logo shown on the studio. The source bytes stay so it can be cropped again.
    @Attribute(.externalStorage) var logoImageData: Data? = nil
    @Attribute(.externalStorage) var logoImageSourceData: Data? = nil
    /// Stable id written into a backup. Empty until the first backup stamps it.
    var archiveID: String = ""

    @Relationship(deleteRule: .nullify, inverse: \Invoice.studio)
    var invoices: [Invoice]

    init(
        name: String = "",
        email: String = "",
        phone: String = "",
        address: String = "",
        isPrimary: Bool = false,
        archived: Bool = false,
        createdAt: Date = .now,
        logoImageData: Data? = nil,
        logoImageSourceData: Data? = nil
    ) {
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
        self.isPrimary = isPrimary
        self.archived = archived
        self.createdAt = createdAt
        self.logoImageData = logoImageData
        self.logoImageSourceData = logoImageSourceData
        self.invoices = []
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "Unnamed studio"
    }

    /// Email, phone, and address, split on line breaks, with blanks removed.
    var detailLines: [String] {
        [email, phone, address].flatMap { value in
            value
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    var letterhead: [String] {
        [displayName] + detailLines
    }
}
