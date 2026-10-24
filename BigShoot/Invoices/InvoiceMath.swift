import Foundation

nonisolated enum InvoiceMath {
    static func lineTotal(quantity: Decimal, unitPrice: Decimal) -> Decimal {
        quantity * unitPrice
    }

    static func total(subtotal: Decimal, tax: Decimal, discount: Decimal, shipping: Decimal) -> Decimal {
        subtotal + tax + shipping - discount
    }

    static func displayStatus(
        stored: InvoiceStatus,
        balance: Decimal,
        dueDate: Date?,
        now: Date = .now
    ) -> InvoiceStatus {
        if stored == .void || stored == .draft { return stored }
        if balance <= 0 { return .paid }
        if let dueDate, dueDate < Calendar.current.startOfDay(for: now) {
            return .overdue
        }
        return .pending
    }

    /// A draft, pending, or overdue invoice still represents money that can be collected.
    static func holdsOpenBalance(
        stored: InvoiceStatus,
        balance: Decimal,
        dueDate: Date?,
        now: Date = .now
    ) -> Bool {
        switch displayStatus(stored: stored, balance: balance, dueDate: dueDate, now: now) {
        case .paid, .void:
            false
        case .draft, .pending, .overdue:
            true
        }
    }

    /// Days from the invoice date to the payment. Same calendar day is zero.
    static func daysToPay(from invoiceDate: Date, paidAt: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: invoiceDate),
            to: calendar.startOfDay(for: paidAt)
        ).day ?? 0
        switch days {
        case ..<(-1):
            return "\(abs(days)) days before the invoice"
        case -1:
            return "1 day before the invoice"
        case 0:
            return "Paid same day"
        case 1:
            return "Paid in 1 day"
        default:
            return "Paid in \(days) days"
        }
    }

    static func dueCountdown(until due: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: due)
        ).day ?? 0
        switch days {
        case ..<(-1):
            return "\(abs(days)) days past due"
        case -1:
            return "1 day past due"
        case 0:
            return "Due today"
        case 1:
            return "1 day left"
        default:
            return "\(days) days left"
        }
    }

    static func nextNumber(among numbers: [String]) -> String {
        let highest = numbers.compactMap { Int($0) }.max() ?? 0
        return String(highest + 1)
    }

    /// Rewrites total and balance from the lines. Used for invoices written in BigShoot.
    static func recalculate(_ invoice: Invoice) {
        let subtotal = invoice.lines.reduce(Decimal.zero) { partial, line in
            partial + line.lineTotal
        }
        invoice.total = total(
            subtotal: subtotal,
            tax: invoice.tax,
            discount: invoice.discount,
            shipping: invoice.shipping
        )
        invoice.balance = invoice.total - invoice.amountPaid
        applyDerivedStatus(invoice)
    }

    /// Keeps the stored ShootQ total and only refreshes status from the balance.
    static func applyDerivedStatus(_ invoice: Invoice, now: Date = .now) {
        guard invoice.status != .void, invoice.status != .draft else { return }
        invoice.status = displayStatus(
            stored: invoice.status,
            balance: invoice.balance,
            dueDate: invoice.dueDate,
            now: now
        )
        if invoice.status == .paid, invoice.paidDate == nil {
            invoice.paidDate = now
        }
    }
}
