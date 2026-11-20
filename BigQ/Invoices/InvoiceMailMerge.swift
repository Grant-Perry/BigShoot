import Foundation
import SwiftData

enum InvoiceMailKey {
    static func existing(for invoice: Invoice) -> String {
        invoice.archiveID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stable id shared with backups. Assigned the first time a letter is saved.
    static func ensure(for invoice: Invoice) -> String {
        let trimmed = existing(for: invoice)
        if !trimmed.isEmpty { return trimmed }
        let assigned = UUID().uuidString
        invoice.archiveID = assigned
        return assigned
    }
}

enum InvoiceMailBuiltin: String, CaseIterable, Identifiable {
    case invoice
    case reminder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invoice: "Invoice"
        case .reminder: "Reminder"
        }
    }
}

enum InvoiceMailPick: Hashable {
    case current
    case builtin(InvoiceMailBuiltin)
    case saved(PersistentIdentifier)
}

enum InvoiceMailMerge {
    /// Visible label for `[Pay Link]`. The address stays in the link, not in the letter.
    static let payLinkPhrase = "You can pay this invoice here"

    static let tokenHint = "These fill from this invoice: [Client Name]  [Studio Name]  [Invoice Number]  [Job Name]  [Due Date]  [Amount Due]  [Remaining Balance]  [Pay Link]  [Letterhead]"

    static let letterVariables: [AgreementVariable] = [
        AgreementVariable("Client Name"),
        AgreementVariable("Studio Name"),
        AgreementVariable(label: "Invoice Number", token: "[Invoice Number]"),
        AgreementVariable("Job Name"),
        AgreementVariable(label: "Due Date", token: "[Due Date]"),
        AgreementVariable(label: "Amount Due", token: "[Amount Due]"),
        AgreementVariable(label: "Remaining Balance", token: "[Remaining Balance]"),
        AgreementVariable(label: "Pay Link", token: "[Pay Link]"),
        AgreementVariable(label: "Letterhead", token: "[Letterhead]"),
    ]

    static let subjectTemplate = "Invoice [Invoice Number] from [Studio Name]"

    static func subject(for invoice: Invoice) -> String {
        fill(subjectTemplate, invoice: invoice)
    }

    static func recipients(for invoice: Invoice) -> [String] {
        let contact = invoice.contact?.email ?? invoice.job?.contact?.email ?? ""
        let trimmed = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }

    static func payURL(for invoice: Invoice) -> String {
        guard !invoice.payToken.isEmpty else { return "" }
        return PayAPI.liveBase
            .appendingPathComponent("pay")
            .appendingPathComponent(invoice.payToken)
            .absoluteString
    }

    static func letter(for invoice: Invoice, reminder: Bool) -> String {
        let quiet = invoice.balance <= 0 && payURL(for: invoice).isEmpty
        return fill(bodyTemplate(reminder: reminder, quiet: quiet), invoice: invoice)
    }

    static func apply(template: EmailTemplate, to invoice: Invoice) -> (subject: String, body: String) {
        (
            fill(template.subject, invoice: invoice),
            fill(template.body, invoice: invoice)
        )
    }

    static func fill(_ text: String, invoice: Invoice) -> String {
        let context = mergeContext(for: invoice)
        let job = invoice.job?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var result = text
        if context.clientName.isEmpty {
            result = result.replacingOccurrences(of: "Hello [Client Name],", with: "Hello,")
        }
        if job.isEmpty {
            result = result.replacingOccurrences(of: " for [Job Name]", with: "")
        }
        result = AgreementMerge.resolve(result, with: context)
        result = QuoteMailMerge.stripHTML(result)
        let extras = [
            "[Letterhead]": QuoteMailMerge.letterhead(for: invoice.studio),
            "[Invoice Number]": context.quoteNumber,
            "[Due Date]": dueText(for: invoice),
            "[Pay Link]": payLinkText(for: invoice),
            "[Client]": context.clientName,
            "[Studio]": context.studioName,
            "[Invoice]": context.quoteNumber,
            "[Job]": context.jobName,
            "[Event]": context.eventDate == "—" ? "" : context.eventDate,
        ]
        return extras.reduce(result) { partial, pair in
            partial.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    static func templatize(_ text: String, invoice: Invoice) -> String {
        let context = mergeContext(for: invoice)
        let letterhead = QuoteMailMerge.letterhead(for: invoice.studio)
        let due = StudioMoney.string(PayLinkAmount.forInvoice(invoice).amount)
        var pairs: [(String, String)] = [
            (letterhead, "[Letterhead]"),
            (payURL(for: invoice), "[Pay Link]"),
            (payLinkPhrase, "[Pay Link]"),
            (due, "[Amount Due]"),
            (context.remainingBalance, "[Remaining Balance]"),
            (context.totalAmount, "[Total Amount]"),
            (context.clientName, "[Client Name]"),
            (context.studioName, "[Studio Name]"),
            (context.jobName, "[Job Name]"),
            (dueText(for: invoice), "[Due Date]"),
            (context.quoteNumber, "[Invoice Number]"),
        ]
        pairs.sort { $0.0.count > $1.0.count }
        var result = text
        for (value, token) in pairs where value.count >= 3 && value != "—" {
            result = result.replacingOccurrences(of: value, with: token)
        }
        let number = context.quoteNumber
        if !number.isEmpty {
            result = result.replacingOccurrences(of: "invoice \(number)", with: "invoice [Invoice Number]")
            result = result.replacingOccurrences(of: "Invoice \(number)", with: "Invoice [Invoice Number]")
        }
        return result
    }

    /// Appends the pay link when a letter was written before the link existed.
    static func ensuringPayLink(_ body: String, invoice: Invoice) -> String {
        let filled = fill(body, invoice: invoice)
        let url = payURL(for: invoice)
        if url.isEmpty || filled.contains(payLinkPhrase) || filled.contains(url) || invoice.balance <= 0 {
            return filled
        }
        let due = StudioMoney.string(PayLinkAmount.forInvoice(invoice).amount)
        let offer = """
        You can pay \(due) here. You can pay that amount or the full balance.

        \(payLinkPhrase)
        """
        let trimmed = filled.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return offer }
        return trimmed + "\n\n" + offer
    }

    // MARK: - Private

    private static let payBlock = """
    You can pay [Amount Due] here. You can pay that amount or the full balance.

    [Pay Link]
    """

    private static func bodyTemplate(reminder: Bool, quiet: Bool) -> String {
        if quiet {
            return """
            Hello [Client Name],

            Attached is invoice [Invoice Number] for [Job Name]. There is no balance due.

            [Letterhead]
            """
        }
        if reminder {
            return """
            Hello [Client Name],

            A reminder that invoice [Invoice Number] for [Job Name] still has a balance of [Remaining Balance], due [Due Date].

            \(payBlock)

            [Letterhead]
            """
        }
        return """
        Hello [Client Name],

        Attached is invoice [Invoice Number] for [Job Name]. The balance is [Remaining Balance], due [Due Date].

        \(payBlock)

        [Letterhead]
        """
    }

    private static func mergeContext(for invoice: Invoice) -> AgreementMergeContext {
        var context = AgreementMerge.context(
            contact: invoice.contact ?? invoice.job?.contact,
            job: invoice.job,
            studio: invoice.studio
        )
        if context.clientName.isEmpty {
            let name = invoice.billToName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { context.clientName = name }
        }
        if context.clientName == "No client" || context.clientName == "Unnamed contact" {
            context.clientName = ""
        }
        let job = invoice.job?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if job.isEmpty { context.jobName = "" }
        let subtotal = invoice.lines.reduce(Decimal.zero) { $0 + $1.lineTotal }
        context.quoteNumber = invoice.displayNumber == "Draft" ? "" : invoice.displayNumber
        context.subtotal = StudioMoney.string(subtotal)
        context.totalAmount = StudioMoney.string(invoice.total)
        context.totalTax = StudioMoney.string(invoice.tax)
        context.totalDiscount = StudioMoney.string(invoice.discount)
        context.remainingBalance = StudioMoney.string(invoice.balance)
        context.retainer = StudioMoney.string(PayLinkAmount.forInvoice(invoice).amount)
        return context
    }

    private static func dueText(for invoice: Invoice) -> String {
        guard let due = invoice.dueDate else { return "on receipt" }
        return StudioDay.string(due)
    }

    private static func payLinkText(for invoice: Invoice) -> String {
        if invoice.balance <= 0, payURL(for: invoice).isEmpty { return "" }
        return payLinkPhrase
    }
}
