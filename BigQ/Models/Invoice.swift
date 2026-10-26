import Foundation
import SwiftData

@Model
final class Invoice {
    #Unique<Invoice>([\.shootqID])

    var shootqID: String?
    var number: String
    var invoiceDate: Date
    var dueDate: Date?
    var paidDate: Date?
    var statusRaw: String
    var tax: Decimal
    /// Fraction snapped onto this invoice, such as 0.066 for 6.6%. Nil or zero means no rate was applied.
    var taxRate: Decimal?
    /// Name of the schedule used when the rate was applied. Empty when the rate was typed for this invoice only.
    var taxScheduleName: String?
    /// Nil on invoices written before this switch. Those charge tax only when they already have a rate or a tax amount.
    var invoiceTaxable: Bool?
    var discount: Decimal
    var shipping: Decimal
    var total: Decimal
    var amountPaid: Decimal
    var balance: Decimal
    var collectManually: Bool
    var remindersDisabled: Bool
    var billToName: String
    var note: String
    /// Sign-off printed at the bottom of the PDF. Empty uses “Thank you.”
    var closing: String = ""
    /// When this invoice was handed to the pipeline. Nil until it is marked submitted.
    var submittedAt: Date?
    var isImported: Bool

    var contact: Contact?
    var job: Job?
    /// Studio that issued this invoice. New invoices take the primary studio and keep it.
    var studio: StudioBrand?

    @Relationship(deleteRule: .cascade, inverse: \InvoiceLine.invoice)
    var lines: [InvoiceLine]

    @Relationship(deleteRule: .cascade, inverse: \PaymentScheduleEntry.invoice)
    var schedule: [PaymentScheduleEntry]

    @Relationship(deleteRule: .cascade, inverse: \PaymentReceipt.invoice)
    var receipts: [PaymentReceipt]

    init(
        shootqID: String? = nil,
        number: String = "",
        invoiceDate: Date = .now,
        dueDate: Date? = nil,
        paidDate: Date? = nil,
        status: InvoiceStatus = .draft,
        tax: Decimal = 0,
        taxRate: Decimal = 0,
        taxScheduleName: String = "",
        invoiceTaxable: Bool? = nil,
        discount: Decimal = 0,
        shipping: Decimal = 0,
        total: Decimal = 0,
        amountPaid: Decimal = 0,
        balance: Decimal = 0,
        collectManually: Bool = true,
        remindersDisabled: Bool = false,
        billToName: String = "",
        note: String = "",
        closing: String = "",
        submittedAt: Date? = nil,
        isImported: Bool = false
    ) {
        self.shootqID = shootqID
        self.number = number
        self.invoiceDate = invoiceDate
        self.dueDate = dueDate
        self.paidDate = paidDate
        self.statusRaw = status.rawValue
        self.tax = tax
        self.taxRate = taxRate
        self.taxScheduleName = taxScheduleName
        self.invoiceTaxable = invoiceTaxable
        self.discount = discount
        self.shipping = shipping
        self.total = total
        self.amountPaid = amountPaid
        self.balance = balance
        self.collectManually = collectManually
        self.remindersDisabled = remindersDisabled
        self.billToName = billToName
        self.note = note
        self.closing = closing
        self.submittedAt = submittedAt
        self.isImported = isImported
        self.lines = []
        self.schedule = []
        self.receipts = []
    }

    var status: InvoiceStatus {
        get { InvoiceStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var displayStatus: InvoiceStatus {
        InvoiceMath.displayStatus(stored: status, balance: balance, dueDate: dueDate)
    }

    /// Still on the books as money to collect. Paid and void invoices are settled.
    var holdsOpenBalance: Bool {
        InvoiceMath.holdsOpenBalance(stored: status, balance: balance, dueDate: dueDate)
    }

    var displayNumber: String {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // Newer ShootQ invoices leave `number` empty and cite the invoice by its id.
        if let shootqID {
            let id = shootqID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty { return id }
        }
        return "Draft"
    }

    /// Due date, plus days left or past while the invoice is still open.
    var dueSummary: String? {
        guard let dueDate else { return nil }
        let day = StudioDay.string(dueDate)
        guard displayStatus != .paid, displayStatus != .void else { return day }
        return "\(day) · \(InvoiceMath.dueCountdown(until: dueDate))"
    }

    var clientName: String {
        if !billToName.isEmpty { return billToName }
        return contact?.displayName ?? "No client"
    }

    /// Paid, void, and unsent drafts cannot take a payment.
    var canRecordPayment: Bool {
        status != .void && status != .draft && balance > 0
    }

    /// Paid and void invoices stay read-only. Open invoices, including ShootQ imports, can be edited.
    /// Whether this invoice should add tax. Older invoices stay on when they already carry tax.
    var appliesTax: Bool {
        if let invoiceTaxable { return invoiceTaxable }
        return tax > 0 || (taxRate ?? 0) > 0
    }

    var canEditLines: Bool {
        status != .void && displayStatus != .paid
    }

    var sortedLines: [InvoiceLine] {
        lines.sorted { $0.position < $1.position }
    }
}
