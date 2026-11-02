import Foundation
import SwiftData

@MainActor
@Observable
final class QuoteDraftModel {
    /// Shared pricing surface — same lines, tax, client, and job editor as invoices.
    var pricing = InvoiceDraftModel()
    var validUntil: Date?
    var agreementTitle = ""
    var agreementHTML = ""
    private var editingID: PersistentIdentifier?
    private var editingStatus: QuoteStatus?
    private var issuedNumber = ""

    var canSave: Bool { pricing.canSave }

    var isMissingTaxRate: Bool { pricing.isMissingTaxRate }

    var isEditing: Bool { editingID != nil }

    var canEditAgreement: Bool {
        editingStatus == nil || editingStatus == .draft || editingStatus == .sent
    }

    var titleNumber: String {
        let trimmed = issuedNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    func load(_ quote: Quote) {
        editingID = quote.persistentModelID
        editingStatus = quote.status
        issuedNumber = quote.number
        validUntil = quote.validUntil
        agreementTitle = quote.agreementTitle
        agreementHTML = quote.agreementHTML
        pricing.load(asQuoteMirror: quote)
    }

    func applyTemplate(_ contract: Contract) {
        agreementTitle = contract.title
        agreementHTML = contract.html
    }

    func clearAgreement() {
        agreementTitle = ""
        agreementHTML = ""
    }

    func makePreview(studio: StudioBrand?) throws -> QuotePreviewSession {
        let schema = Schema(versionedSchema: StudioSchemaV10.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let quote = Quote(
            number: issuedNumber,
            quoteDate: pricing.invoiceDate,
            validUntil: validUntil,
            status: .draft,
            tax: pricing.tax,
            taxRate: pricing.calculatesTax ? pricing.taxRate : 0,
            taxScheduleName: pricing.calculatesTax ? pricing.taxScheduleName : "",
            invoiceTaxable: pricing.invoiceTaxable,
            discount: pricing.discount,
            shipping: pricing.shipping,
            billToName: pricing.contact?.displayName ?? "",
            note: pricing.note,
            closing: pricing.closing,
            agreementTitle: agreementTitle,
            agreementHTML: agreementHTML
        )
        context.insert(quote)
        if let studio {
            let copy = StudioBrand(
                name: studio.name,
                email: studio.email,
                phone: studio.phone,
                address: studio.address,
                isPrimary: studio.isPrimary,
                logoImageData: studio.logoImageData,
                logoImageSourceData: studio.logoImageSourceData
            )
            context.insert(copy)
            quote.studio = copy
        }
        if let contact = pricing.contact {
            let copy = Contact(fullName: contact.displayName, email: contact.email)
            context.insert(copy)
            quote.contact = copy
        }
        if let job = pricing.job {
            let copy = Job(name: job.name, eventDate: job.eventDate, jobType: job.jobType)
            context.insert(copy)
            quote.job = copy
        }
        for (position, line) in pricing.lines.enumerated() {
            let copy = QuoteLine(
                name: line.name,
                detail: line.detail,
                quantity: line.quantity,
                unitPrice: line.unitPrice,
                position: position,
                taxable: line.taxable
            )
            copy.quote = quote
            context.insert(copy)
        }
        QuoteMath.recalculate(quote)
        return QuotePreviewSession(container: container, context: context, quote: quote)
    }

    func save(in context: ModelContext, markSent: Bool) throws -> Quote {
        if pricing.isMissingTaxRate {
            pricing.invoiceTaxable = true
            throw InvoiceDraftError.missingTaxRate
        }
        let quote = try preparedQuote(in: context)
        quote.contact = pricing.contact
        quote.job = pricing.job
        quote.quoteDate = pricing.invoiceDate
        quote.validUntil = validUntil
        quote.tax = pricing.tax
        quote.taxRate = pricing.calculatesTax ? pricing.taxRate : 0
        quote.taxScheduleName = pricing.calculatesTax ? pricing.taxScheduleName : ""
        quote.invoiceTaxable = pricing.invoiceTaxable
        quote.discount = pricing.discount
        quote.shipping = pricing.shipping
        quote.note = pricing.note
        quote.closing = pricing.closing
        quote.billToName = pricing.contact?.displayName ?? quote.billToName
        quote.agreementTitle = agreementTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        quote.agreementHTML = agreementHTML
        replaceLines(on: quote, in: context)
        if markSent {
            if quote.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let numbers = try context.fetch(FetchDescriptor<Quote>()).map(\.number)
                quote.number = QuoteMath.nextNumber(among: numbers)
            }
            if quote.status == .draft {
                quote.status = .sent
            }
            quote.sentAt = quote.sentAt ?? .now
        }
        QuoteMath.recalculate(quote)
        try context.save()
        issuedNumber = quote.number
        editingID = quote.persistentModelID
        editingStatus = quote.status
        return quote
    }

    private func preparedQuote(in context: ModelContext) throws -> Quote {
        if let editingID, let existing = context.model(for: editingID) as? Quote {
            return existing
        }
        let quote = Quote(status: .draft)
        context.insert(quote)
        quote.studio = try StudioBrandDirectory.primary(in: context)
        return quote
    }

    private func replaceLines(on quote: Quote, in context: ModelContext) {
        for line in quote.lines {
            context.delete(line)
        }
        quote.lines.removeAll()
        let named = pricing.lines.enumerated().filter {
            !$0.element.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for (position, draft) in named {
            let line = QuoteLine(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                detail: draft.detail,
                quantity: draft.quantity,
                unitPrice: draft.unitPrice,
                position: position,
                taxable: draft.taxable
            )
            line.quote = quote
            line.catalogItem = draft.catalogItem
            context.insert(line)
        }
    }
}

extension InvoiceDraftModel {
    /// Loads quote pricing into the shared invoice draft surface without touching invoice IDs.
    func load(asQuoteMirror quote: Quote) {
        contact = quote.contact
        job = quote.job
        invoiceDate = quote.quoteDate
        dueDate = quote.validUntil ?? invoiceDate
        syncNetDaysFromDueDate()
        applyTaxFields(
            tax: quote.tax,
            taxRate: quote.taxRate ?? 0,
            taxScheduleName: quote.taxScheduleName ?? "",
            invoiceTaxable: quote.appliesTax
        )
        discount = quote.discount
        shipping = quote.shipping
        note = quote.note
        closing = quote.closing
        lines = quote.sortedLines.map { line in
            DraftLine(
                name: line.name,
                detail: line.detail,
                quantity: line.quantity,
                unitPrice: line.unitPrice,
                taxable: line.taxable ?? false,
                catalogItem: line.catalogItem
            )
        }
        fillEmptyNoteFromJob()
    }
}
