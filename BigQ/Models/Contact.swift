import Foundation
import SwiftData

@Model
final class Contact {
    #Unique<Contact>([\.shootqID])

    var shootqID: String?
    var firstName: String
    var lastName: String
    var fullName: String
    var companyName: String
    var email: String
    var phone: String
    var address: String
    var anniversary: Date?
    var archived: Bool
    var createdAt: Date
    /// Stable id written into a backup. Empty until the first backup stamps it.
    var archiveID: String = ""

    @Relationship(deleteRule: .nullify, inverse: \Job.contact)
    var jobs: [Job]

    @Relationship(deleteRule: .nullify, inverse: \Job.bride)
    var jobsAsBride: [Job]

    @Relationship(deleteRule: .nullify, inverse: \Job.groom)
    var jobsAsGroom: [Job]

    @Relationship(deleteRule: .nullify, inverse: \Invoice.contact)
    var invoices: [Invoice]

    @Relationship(deleteRule: .nullify, inverse: \ContractSignature.contact)
    var contractSignatures: [ContractSignature]

    init(
        shootqID: String? = nil,
        firstName: String = "",
        lastName: String = "",
        fullName: String = "",
        companyName: String = "",
        email: String = "",
        phone: String = "",
        address: String = "",
        anniversary: Date? = nil,
        archived: Bool = false,
        createdAt: Date = .now
    ) {
        self.shootqID = shootqID
        self.firstName = firstName
        self.lastName = lastName
        self.fullName = fullName
        self.companyName = companyName
        self.email = email
        self.phone = phone
        self.address = address
        self.anniversary = anniversary
        self.archived = archived
        self.createdAt = createdAt
        self.jobs = []
        self.jobsAsBride = []
        self.jobsAsGroom = []
        self.invoices = []
        self.contractSignatures = []
    }

    var displayName: String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let combined = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !combined.isEmpty { return combined }
        if !companyName.isEmpty { return companyName }
        return "Unnamed contact"
    }

    /// First name on the contact, or the first word of the stored full name.
    var givenName: String {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return first }
        return storedFullNameParts.first ?? ""
    }

    /// Last name on the contact, or the rest of the stored full name.
    var familyName: String {
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { return last }
        return storedFullNameParts.dropFirst().joined(separator: " ")
    }

    private var storedFullNameParts: [String] {
        fullName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }
}
