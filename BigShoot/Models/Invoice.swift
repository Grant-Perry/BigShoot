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
    var discount: Decimal
    var shipping: Decimal
    var total: Decimal
    var amountPaid: Decimal
    var balance: Decimal
    var collectManually: Bool
    var remindersDisabled: Bool
    var billToName: String
    var note: String
    var isImported: Bool

    var contact: Contact?
    var job: Job?

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
        discount: Decimal = 0,
        shipping: Decimal = 0,
        total: Decimal = 0,
        amountPaid: Decimal = 0,
        balance: Decimal = 0,
        collectManually: Bool = true,
        remindersDisabled: Bool = false,
        billToName: String = "",
        note: String = "",
        isImported: Bool = false
    ) {
        self.shootqID = shootqID
        self.number = number
        self.invoiceDate = invoiceDate
        self.dueDate = dueDate
        self.paidDate = paidDate
        self.statusRaw = status.rawValue
        self.tax = tax
        self.discount = discount
        self.shipping = shipping
        self.total = total
        self.amountPaid = amountPaid
        self.balance = balance
        self.collectManually = collectManually
        self.remindersDisabled = remindersDisabled
        self.billToName = billToName
        self.note = note
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

    var displayNumber: String {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == .draft || trimmed.isEmpty { return "Draft" }
        return trimmed
    }

    var clientName: String {
        if !billToName.isEmpty { return billToName }
        return contact?.displayName ?? "No client"
    }

    /// Imported paid and void invoices stay read-only. Open imported invoices can still take a payment.
    var canRecordPayment: Bool {
        status != .void && status != .draft && balance > 0
    }

    var canEditLines: Bool {
        !isImported && status != .void && displayStatus != .paid
    }

    var sortedLines: [InvoiceLine] {
        lines.sorted { $0.position < $1.position }
    }
}
