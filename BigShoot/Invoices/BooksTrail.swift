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

    static func noteEdited(_ invoice: Invoice, before: EditSnapshot, in context: ModelContext) {
        write(
            .edited,
            invoice: invoice,
            amount: invoice.total,
            detail: editDetail(number: invoice.displayNumber, before: before, after: EditSnapshot(invoice)),
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
        notePayment(invoice, amount: amount, methodName: method.title, in: context)
    }

    static func notePayment(_ invoice: Invoice, amount: Decimal, methodName: String, in context: ModelContext) {
        write(
            .paymentApplied,
            invoice: invoice,
            amount: amount,
            detail: "Applied \(StudioMoney.string(amount)) by \(methodName) to \(invoice.displayNumber).",
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

    static func editDetail(number: String, before: EditSnapshot, after: EditSnapshot) -> String {
        let changes = editChanges(before: before, after: after)
        guard !changes.isEmpty else {
            return "Edited \(number). Nothing on the invoice changed."
        }
        return "Edited \(number). " + changes.joined(separator: ". ") + "."
    }

    private static func editChanges(before: EditSnapshot, after: EditSnapshot) -> [String] {
        var changes: [String] = []
        if before.total != after.total {
            changes.append("Total \(StudioMoney.string(before.total)) → \(StudioMoney.string(after.total))")
        }
        if before.balance != after.balance {
            changes.append("Balance \(StudioMoney.string(before.balance)) → \(StudioMoney.string(after.balance))")
        }
        if before.clientName != after.clientName {
            changes.append("Client \(before.clientName) → \(after.clientName)")
        }
        if before.jobName != after.jobName {
            changes.append("Job \(jobLabel(before.jobName)) → \(jobLabel(after.jobName))")
        }
        if !sameDay(before.invoiceDate, after.invoiceDate) {
            changes.append("Invoice date \(StudioDay.string(before.invoiceDate)) → \(StudioDay.string(after.invoiceDate))")
        }
        if !sameDay(before.dueDate, after.dueDate) {
            changes.append("Due \(StudioDay.string(before.dueDate)) → \(StudioDay.string(after.dueDate))")
        }
        if before.invoiceTaxable != after.invoiceTaxable {
            changes.append("Invoice taxable \(before.invoiceTaxable ? "On" : "Off") → \(after.invoiceTaxable ? "On" : "Off")")
        }
        if before.tax != after.tax {
            changes.append("Tax \(StudioMoney.string(before.tax)) → \(StudioMoney.string(after.tax))")
        }
        if before.taxRate != after.taxRate {
            changes.append("Tax rate \(TaxRateInput.percentText(for: before.taxRate))% → \(TaxRateInput.percentText(for: after.taxRate))%")
        }
        if before.taxScheduleName != after.taxScheduleName {
            changes.append("Tax schedule \(scheduleLabel(before.taxScheduleName)) → \(scheduleLabel(after.taxScheduleName))")
        }
        if before.discount != after.discount {
            changes.append("Discount \(StudioMoney.string(before.discount)) → \(StudioMoney.string(after.discount))")
        }
        if before.shipping != after.shipping {
            changes.append("Shipping \(StudioMoney.string(before.shipping)) → \(StudioMoney.string(after.shipping))")
        }
        changes.append(contentsOf: lineChanges(before: before.lines, after: after.lines))
        if before.note != after.note {
            changes.append(after.note.isEmpty ? "Note cleared" : "Note updated")
        }
        return changes
    }

    private static func lineChanges(before: [EditSnapshot.Line], after: [EditSnapshot.Line]) -> [String] {
        var remaining = before
        var changes: [String] = []
        for line in after {
            if let index = remaining.firstIndex(of: line) {
                remaining.remove(at: index)
                continue
            }
            if let index = remaining.firstIndex(where: { $0.name == line.name }) {
                let old = remaining.remove(at: index)
                changes.append(lineChange(from: old, to: line))
            } else {
                changes.append("Added \(line.name), \(priced(line))")
            }
        }
        for line in remaining {
            changes.append("Removed \(line.name), \(priced(line))")
        }
        return changes
    }

    private static func lineChange(from old: EditSnapshot.Line, to new: EditSnapshot.Line) -> String {
        var pieces: [String] = []
        if old.name == new.name {
            pieces.append(new.name)
        } else {
            pieces.append("\(old.name) → \(new.name)")
        }
        if old.quantity != new.quantity || old.unitPrice != new.unitPrice {
            pieces.append("\(priced(old)) → \(priced(new))")
        }
        if old.detail != new.detail {
            pieces.append("detail updated")
        }
        return pieces.joined(separator: ", ")
    }

    private static func priced(_ line: EditSnapshot.Line) -> String {
        let quantity = line.quantity.formatted(.number.precision(.fractionLength(0...2)))
        return "\(quantity) × \(StudioMoney.string(line.unitPrice))"
    }

    private static func jobLabel(_ name: String) -> String {
        name.isEmpty ? "No job" : name
    }

    private static func scheduleLabel(_ name: String) -> String {
        name.isEmpty ? "None" : name
    }

    private static func sameDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (left?, right?):
            Calendar.current.isDate(left, inSameDayAs: right)
        default:
            false
        }
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

extension BooksTrail {
    /// Values copied before a save, so the audit line can name what changed.
    struct EditSnapshot: Equatable {
        struct Line: Equatable {
            var name: String
            var quantity: Decimal
            var unitPrice: Decimal
            var detail: String
        }

        var clientName: String
        var jobName: String
        var invoiceDate: Date
        var dueDate: Date?
        var tax: Decimal
        var taxRate: Decimal
        var taxScheduleName: String
        var invoiceTaxable: Bool
        var discount: Decimal
        var shipping: Decimal
        var note: String
        var total: Decimal
        var balance: Decimal
        var lines: [Line]

        init(
            clientName: String,
            jobName: String,
            invoiceDate: Date,
            dueDate: Date?,
            tax: Decimal,
            taxRate: Decimal = 0,
            taxScheduleName: String = "",
            invoiceTaxable: Bool = false,
            discount: Decimal,
            shipping: Decimal,
            note: String,
            total: Decimal,
            balance: Decimal,
            lines: [Line]
        ) {
            self.clientName = clientName
            self.jobName = jobName
            self.invoiceDate = invoiceDate
            self.dueDate = dueDate
            self.tax = tax
            self.taxRate = taxRate
            self.taxScheduleName = taxScheduleName
            self.invoiceTaxable = invoiceTaxable
            self.discount = discount
            self.shipping = shipping
            self.note = note
            self.total = total
            self.balance = balance
            self.lines = lines
        }

        init(_ invoice: Invoice) {
            clientName = invoice.clientName
            jobName = invoice.job?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            invoiceDate = invoice.invoiceDate
            dueDate = invoice.dueDate
            tax = invoice.tax
            taxRate = invoice.taxRate ?? 0
            taxScheduleName = invoice.taxScheduleName ?? ""
            invoiceTaxable = invoice.appliesTax
            discount = invoice.discount
            shipping = invoice.shipping
            note = invoice.note
            total = invoice.total
            balance = invoice.balance
            lines = invoice.sortedLines.map {
                Line(name: $0.name, quantity: $0.quantity, unitPrice: $0.unitPrice, detail: $0.detail)
            }
        }
    }
}
