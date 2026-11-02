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

        if quote.hasAgreement {
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

    private static func attachSignedContract(from quote: Quote, in context: ModelContext, at date: Date) {
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
            displayName: quote.clientName,
            completed: true,
            signedAt: date,
            contact: quote.contact
        )
        signer.contract = contract
        context.insert(signer)
    }
}
