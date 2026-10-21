import Foundation
import SwiftData

/// Writes the audit trail. Events store copies, so a later edit or delete cannot rewrite them.
enum BooksTrail {
    static func noteCreated(_ invoice: Invoice, in context: ModelContext) {
        write(
            .created,
            invoice: invoice,
            amount: invoice.total,
            detail: "Created \(invoice.displayNumber) for \(invoice.clientName).",
            in: context
        )
    }

    static func noteEdited(_ invoice: Invoice, in context: ModelContext) {
        write(
            .edited,
            invoice: invoice,
            amount: invoice.total,
            detail: "Edited \(invoice.displayNumber). Total is \(StudioMoney.string(invoice.total)).",
            in: context
        )
    }

    static func noteMarkedSent(_ invoice: Invoice, in context: ModelContext) {
        write(
            .markedSent,
            invoice: invoice,
            amount: invoice.total,
            detail: "Marked \(invoice.displayNumber) sent to \(invoice.clientName).",
            in: context
        )
    }

    static func notePayment(_ invoice: Invoice, amount: Decimal, method: PaymentMethod, in context: ModelContext) {
        write(
            .paymentApplied,
            invoice: invoice,
            amount: amount,
            detail: "Applied \(StudioMoney.string(amount)) by \(method.title) to \(invoice.displayNumber).",
            in: context
        )
    }

    static func noteDeleted(_ invoice: Invoice, in context: ModelContext) {
        let paid = invoice.amountPaid
        var detail = "Deleted \(invoice.displayNumber) for \(invoice.clientName). Balance was \(StudioMoney.string(invoice.balance))."
        if paid > 0 {
            detail += " Payments of \(StudioMoney.string(paid)) were removed with it."
        }
        write(.deleted, invoice: invoice, amount: invoice.balance, detail: detail, in: context)
    }

    static func events(for invoice: Invoice, in events: [BooksEvent]) -> [BooksEvent] {
        guard let key = invoice.shootqID, !key.isEmpty else { return [] }
        return events.filter { $0.invoiceKey == key }
    }

    @discardableResult
    static func ensureKey(_ invoice: Invoice) -> String {
        if let key = invoice.shootqID, !key.isEmpty { return key }
        let key = UUID().uuidString
        invoice.shootqID = key
        return key
    }

    private static func write(
        _ kind: BooksEventKind,
        invoice: Invoice,
        amount: Decimal,
        detail: String,
        in context: ModelContext
    ) {
        let event = BooksEvent(
            kind: kind,
            invoiceKey: ensureKey(invoice),
            invoiceNumber: invoice.displayNumber,
            clientName: invoice.clientName,
            amount: amount,
            detail: detail
        )
        context.insert(event)
    }
}
