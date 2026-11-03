import Foundation
import SwiftData

@MainActor
enum QuoteConverter {
    enum Failure: LocalizedError {
        case alreadyConverted
        case missingClient
        case voided

        var errorDescription: String? {
            switch self {
            case .alreadyConverted: "This quote already became an invoice."
            case .missingClient: "Pick a client before converting."
            case .voided: "A void quote cannot become an invoice."
            }
        }
    }

    /// Marks the quote signed and creates a pending invoice from its lines.
    @discardableResult
    static func convertToInvoice(
        _ quote: Quote,
        evidence: Data? = nil,
        in context: ModelContext,
        at date: Date = .now
    ) throws -> Invoice {
        guard quote.convertedInvoice == nil else { throw Failure.alreadyConverted }
        guard quote.status != .void else { throw Failure.voided }
        guard quote.contact != nil || !quote.billToName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.missingClient
        }

        if let evidence {
            quote.signedEvidenceData = evidence
        }

        let invoice = Invoice(
            invoiceDate: date,
            dueDate: dueDate(for: quote, from: date),
            status: .pending,
            tax: quote.tax,
            taxRate: quote.taxRate ?? 0,
            taxScheduleName: quote.taxScheduleName ?? "",
            invoiceTaxable: quote.invoiceTaxable,
            discount: quote.discount,
            shipping: quote.shipping,
            billToName: quote.billToName,
            note: quote.note,
            closing: quote.closing,
            isImported: false
        )
        context.insert(invoice)
        invoice.contact = quote.contact
        invoice.job = quote.job
        invoice.studio = quote.studio ?? (try? StudioBrandDirectory.primary(in: context))
        let numbers = try context.fetch(FetchDescriptor<Invoice>()).map(\.number)
        invoice.number = InvoiceMath.nextNumber(among: numbers)

        for line in quote.sortedLines {
            let copy = InvoiceLine(
                name: line.name,
                detail: line.detail,
                quantity: line.quantity,
                unitPrice: line.unitPrice,
                position: line.position,
                taxable: line.taxable ?? false
            )
            copy.invoice = invoice
            copy.catalogItem = line.catalogItem
            context.insert(copy)
        }
        InvoiceMath.recalculate(invoice)

        quote.status = .signed
        quote.signedAt = date
        quote.convertedInvoice = invoice
        copyPaymentSchedule(from: quote, to: invoice, signedAt: date, in: context)

        if quote.hasAgreement {
            quote.agreementHTML = AgreementMerge.resolve(
                quote.agreementHTML,
                with: AgreementMerge.context(
                    contact: quote.job?.contact ?? quote.contact,
                    job: quote.job,
                    studio: quote.studio,
                    quote: quote
                )
            )
            attachSignedContract(from: quote, in: context, at: date)
        }

        BooksTrail.noteCreated(invoice, in: context)
        BooksTrail.noteMarkedSent(invoice, in: context)
        try context.save()
        return invoice
    }

    private static func dueDate(for quote: Quote, from date: Date) -> Date {
        if let validUntil = quote.validUntil { return validUntil }
        let days = InvoiceDraftModel.defaultNetDays
        let anchor = quote.job?.eventDate ?? date
        return Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: anchor))
            ?? date
    }

    private static func copyPaymentSchedule(
        from quote: Quote,
        to invoice: Invoice,
        signedAt: Date,
        in context: ModelContext
    ) {
        guard quote.paymentScheduleMode != .none else { return }
        let drafts: [DraftPaymentTerm] = quote.sortedPaymentTerms.map { term in
            DraftPaymentTerm(
                title: term.title,
                amountMode: term.amountMode,
                percent: term.percent,
                fixedAmount: term.fixedAmount,
                dueMode: term.dueMode,
                daysBeforeEvent: term.daysBeforeEvent,
                fixedDueDate: term.fixedDueDate ?? signedAt,
                amount: term.amount
            )
        }
        var recalculated = drafts
        QuotePaymentSchedule.recalculate(&recalculated, total: invoice.total)
        for (index, term) in recalculated.enumerated() {
            let due = QuotePaymentSchedule.resolveDue(
                term,
                signatureDate: signedAt,
                eventDate: quote.job?.eventDate,
                fallback: signedAt
            )
            let entry = PaymentScheduleEntry(
                due: due,
                amount: term.amount,
                amountPaid: 0,
                balance: term.amount,
                status: term.title.isEmpty ? "Payment \(index + 1)" : term.title
            )
            entry.invoice = invoice
            context.insert(entry)
        }
        if let lastDue = invoice.schedule.compactMap(\.due).max() {
            invoice.dueDate = lastDue
        }
    }

    private static func attachSignedContract(from quote: Quote, in context: ModelContext, at date: Date) {
        let client = quote.job?.contact ?? quote.contact
        let contract = Contract(
            title: quote.agreementTitle.isEmpty ? "Agreement" : quote.agreementTitle,
            status: "signed",
            html: quote.agreementHTML,
            eventLabel: quote.job?.eventDate.map(StudioDay.string) ?? "",
            sentAt: quote.sentAt ?? date,
            isTemplate: false,
            job: quote.job
        )
        context.insert(contract)
        let signer = ContractSignature(
            displayName: client?.displayName ?? quote.clientName,
            completed: true,
            signedAt: date,
            contact: client
        )
        signer.contract = contract
        context.insert(signer)
    }
}
