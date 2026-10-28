import Foundation
import SwiftData

/// Takes one payment recorded in BigQ back off its invoice. ShootQ receipts stay put.
enum PaymentRemoval {
    enum Failure: Error, Equatable, LocalizedError {
        case imported
        case missingInvoice

        var errorDescription: String? {
            switch self {
            case .imported:
                "This payment came from ShootQ and stays on the invoice."
            case .missingInvoice:
                "This payment isn’t attached to an invoice."
            }
        }
    }

    static let title = "Remove this payment?"

    static func canRemove(_ receipt: PaymentReceipt) -> Bool {
        let key = receipt.shootqID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty
    }

    static func message(for receipt: PaymentReceipt) -> String {
        let amount = StudioMoney.string(receipt.amount)
        let when = StudioDay.string(receipt.paidAt)
        let method = receipt.methodTitle
        guard let invoice = receipt.invoice else {
            return "\(amount) by \(method), paid \(when), isn’t attached to an invoice."
        }
        let restoredPaid = max(.zero, invoice.amountPaid - receipt.amount)
        let balance = invoice.total - restoredPaid
        return "\(amount) by \(method), paid \(when), comes off \(invoice.displayNumber). \(invoice.clientName) goes back to a balance of \(StudioMoney.string(balance)), and this amount leaves collections. The audit trail keeps the payment and this removal."
    }

    static func remove(_ receipt: PaymentReceipt, in context: ModelContext) throws {
        guard canRemove(receipt) else { throw Failure.imported }
        guard let invoice = receipt.invoice else { throw Failure.missingInvoice }
        let amount = receipt.amount
        let paidAt = receipt.paidAt
        BooksTrail.notePaymentRemoved(
            invoice,
            amount: amount,
            methodName: receipt.methodTitle,
            paidAt: paidAt,
            in: context
        )
        invoice.amountPaid = max(.zero, invoice.amountPaid - amount)
        invoice.balance = invoice.total - invoice.amountPaid
        if invoice.balance > 0,
           let paidDate = invoice.paidDate,
           Calendar.current.isDate(paidDate, inSameDayAs: paidAt) {
            invoice.paidDate = nil
        }
        context.delete(receipt)
        InvoiceMath.applyDerivedStatus(invoice)
        try context.save()
    }
}
