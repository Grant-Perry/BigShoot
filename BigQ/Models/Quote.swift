import Foundation
import SwiftData

@Model
final class Quote {
    var number: String
    var quoteDate: Date
    var validUntil: Date?
    var statusRaw: String
    var tax: Decimal
    var taxRate: Decimal?
    var taxScheduleName: String?
    var invoiceTaxable: Bool?
    var discount: Decimal
    var shipping: Decimal
    var total: Decimal
    var billToName: String
    var note: String
    var closing: String
    /// Snapshot of the agreement title attached when the quote was built.
    var agreementTitle: String
    /// Snapshot of the agreement body. Templates can change later without rewriting sent quotes.
    var agreementHTML: String
    var sentAt: Date?
    var signedAt: Date?
    /// Optional PDF the client returned. Phase 1 evidence only.
    @Attribute(.externalStorage) var signedEvidenceData: Data?
    var archiveID: String = ""

    var contact: Contact?
    var job: Job?
    var studio: StudioBrand?

    @Relationship(deleteRule: .nullify, inverse: \Invoice.sourceQuote)
    var convertedInvoice: Invoice?

    @Relationship(deleteRule: .cascade, inverse: \QuoteLine.quote)
    var lines: [QuoteLine]

    init(
        number: String = "",
        quoteDate: Date = .now,
        validUntil: Date? = nil,
        status: QuoteStatus = .draft,
        tax: Decimal = 0,
        taxRate: Decimal? = nil,
        taxScheduleName: String? = nil,
        invoiceTaxable: Bool? = nil,
        discount: Decimal = 0,
        shipping: Decimal = 0,
        total: Decimal = 0,
        billToName: String = "",
        note: String = "",
        closing: String = "",
        agreementTitle: String = "",
        agreementHTML: String = "",
        sentAt: Date? = nil,
        signedAt: Date? = nil
    ) {
        self.number = number
        self.quoteDate = quoteDate
        self.validUntil = validUntil
        self.statusRaw = status.rawValue
        self.tax = tax
        self.taxRate = taxRate
        self.taxScheduleName = taxScheduleName
        self.invoiceTaxable = invoiceTaxable
        self.discount = discount
        self.shipping = shipping
        self.total = total
        self.billToName = billToName
        self.note = note
        self.closing = closing
        self.agreementTitle = agreementTitle
        self.agreementHTML = agreementHTML
        self.sentAt = sentAt
        self.signedAt = signedAt
        self.lines = []
    }

    var status: QuoteStatus {
        get { QuoteStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var displayNumber: String {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Draft" : trimmed
    }

    var clientName: String {
        if !billToName.isEmpty { return billToName }
        return contact?.displayName ?? "No client"
    }

    var hasAgreement: Bool {
        !agreementTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !agreementHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var appliesTax: Bool {
        if let invoiceTaxable { return invoiceTaxable }
        return tax > 0 || (taxRate ?? 0) > 0
    }

    var canEdit: Bool {
        status == .draft || status == .sent
    }

    var canSend: Bool {
        status == .draft || status == .sent
    }

    var canMarkSigned: Bool {
        status == .sent || status == .draft
    }

    var sortedLines: [QuoteLine] {
        lines.sorted { $0.position < $1.position }
    }
}
