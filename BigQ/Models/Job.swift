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
    var paymentScheduleModeRaw: String = QuotePaymentScheduleMode.none.rawValue

    var contact: Contact?

    @Relationship(deleteRule: .nullify, inverse: \Invoice.job)
    var invoices: [Invoice]

    @Relationship(deleteRule: .nullify, inverse: \Quote.job)
    var quotes: [Quote]

    @Relationship(deleteRule: .nullify, inverse: \Contract.job)
    var contracts: [Contract]

    @Relationship(deleteRule: .cascade, inverse: \JobPaymentTerm.job)
    var paymentTerms: [JobPaymentTerm]

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
        self.quotes = []
        self.contracts = []
        self.paymentTerms = []
    }

    var paymentScheduleMode: QuotePaymentScheduleMode {
        get { QuotePaymentScheduleMode(rawValue: paymentScheduleModeRaw) ?? .none }
        set { paymentScheduleModeRaw = newValue.rawValue }
    }

    var sortedPaymentTerms: [JobPaymentTerm] {
        paymentTerms.sorted { $0.position < $1.position }
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
