import Foundation
import SwiftData

enum InvoiceRemoval {
    static func title(for invoice: Invoice) -> String {
        "Delete \(invoice.displayNumber)?"
    }

    static func message(for invoice: Invoice) -> String {
        var parts = ["\(invoice.clientName) · balance \(StudioMoney.string(invoice.balance))."]
        if invoice.amountPaid > 0 {
            parts.append("Payments of \(StudioMoney.string(invoice.amountPaid)) are removed with the invoice and drop out of collections.")
        } else {
            parts.append("No payments are recorded on it.")
        }
        parts.append("The audit trail keeps the number, client, balance, and time. This cannot be undone.")
        return parts.joined(separator: " ")
    }

    static func remove(_ invoice: Invoice, in context: ModelContext) throws {
        BooksTrail.noteDeleted(invoice, in: context)
        context.delete(invoice)
        try context.save()
    }
}
