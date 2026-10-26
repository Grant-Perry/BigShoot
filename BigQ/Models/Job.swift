import Foundation
import SwiftData

@Model
final class Job {
    #Unique<Job>([\.shootqID])

    var shootqID: String?
    var name: String
    var eventDate: Date?
    var jobType: String
    var status: String
    var archived: Bool
    /// Stable id written into a backup. Empty until the first backup stamps it.
    var archiveID: String = ""

    var contact: Contact?

    @Relationship(deleteRule: .nullify, inverse: \Invoice.job)
    var invoices: [Invoice]

    @Relationship(deleteRule: .nullify, inverse: \Contract.job)
    var contracts: [Contract]

    init(
        shootqID: String? = nil,
        name: String = "",
        eventDate: Date? = nil,
        jobType: String = "",
        status: String = "",
        archived: Bool = false,
        contact: Contact? = nil
    ) {
        self.shootqID = shootqID
        self.name = name
        self.eventDate = eventDate
        self.jobType = jobType
        self.status = status
        self.archived = archived
        self.contact = contact
        self.invoices = []
        self.contracts = []
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled job" : trimmed
    }

    var invoicesWithOpenBalance: [Invoice] {
        invoices
            .filter(\.holdsOpenBalance)
            .sorted { $0.invoiceDate > $1.invoiceDate }
    }
}
