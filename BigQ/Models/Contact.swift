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
}
