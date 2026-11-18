import Foundation
import SwiftData

/// Applies a receipt and keeps the invoice balance in one place.
enum PayLedger {
    struct Applied: Equatable {
        var amount: Decimal
        var alreadyRecorded: Bool
    }

    @MainActor
    @discardableResult
    static func apply(
        amount: Decimal,
        paidAt: Date,
        methodKey: String,
        methodName: String,
        transactionID: String,
        to invoice: Invoice,
        in context: ModelContext
    ) throws -> Applied {
        let trimmedID = transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedID.isEmpty, invoice.receipts.contains(where: { $0.processorTransactionID == trimmedID }) {
            return Applied(amount: amount, alreadyRecorded: true)
        }
        guard amount > 0 else {
            return Applied(amount: 0, alreadyRecorded: false)
        }
        let receipt = PaymentReceipt(paidAt: paidAt, amount: amount)
        receipt.methodRaw = methodKey
        receipt.processorTransactionID = trimmedID
        receipt.invoice = invoice
        context.insert(receipt)
        BooksTrail.notePayment(invoice, amount: amount, methodName: methodName, in: context)
        invoice.amountPaid += amount
        invoice.balance = invoice.total - invoice.amountPaid
        if invoice.status == .draft {
            invoice.status = .pending
        }
        InvoiceMath.applyDerivedStatus(invoice, now: paidAt)
        try context.save()
        return Applied(amount: amount, alreadyRecorded: false)
    }
}
