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
    var paymentScheduleMode: QuotePaymentScheduleMode = .none
    var paymentTerms: [DraftPaymentTerm] = []
    private var editingID: PersistentIdentifier?
    private var editingStatus: QuoteStatus?
    private var issuedNumber = ""

    var canSave: Bool { pricing.canSave }

    var isMissingTaxRate: Bool { pricing.isMissingTaxRate }

    var isEditing: Bool { editingID != nil }

    var titleNumber: String {
        let trimmed = issuedNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    var paymentScheduleIsComplete: Bool {
        switch paymentScheduleMode {
        case .none:
            true
        case .scheduled, .custom:
            !paymentTerms.isEmpty && QuotePaymentSchedule.isComplete(paymentTerms, total: pricing.total)
        }
    }

    var paymentAllocated: Decimal {
        QuotePaymentSchedule.allocated(in: paymentTerms)
    }

    func load(_ quote: Quote) {
        editingID = quote.persistentModelID
        editingStatus = quote.status
        issuedNumber = quote.number
        validUntil = quote.validUntil
        agreementTitle = quote.agreementTitle
        agreementHTML = quote.agreementHTML
        paymentScheduleMode = quote.paymentScheduleMode
        paymentTerms = quote.sortedPaymentTerms.map { term in
            DraftPaymentTerm(
                title: term.title,
                amountMode: term.amountMode,
                percent: term.percent,
                fixedAmount: term.fixedAmount,
                dueMode: term.dueMode,
                daysBeforeEvent: term.daysBeforeEvent,
                fixedDueDate: term.fixedDueDate ?? .now,
                amount: term.amount
            )
        }
        pricing.load(asQuoteMirror: quote)
        refreshPaymentAmounts()
    }

    func applyTemplate(_ contract: Contract, askAnswers: [String: String] = [:]) {
        agreementTitle = contract.title
        agreementHTML = AgreementAskField.apply(contract.html, answers: askAnswers)
    }

    /// Pulls the job’s attached agreement into this quote when one exists.
    @discardableResult
    func adoptAgreement(from job: Job?, studio: StudioBrand? = nil) -> Bool {
        guard let job, let contract = ContractLinks.preferredAgreement(for: job) else { return false }
        agreementTitle = contract.title.isEmpty ? "Agreement" : contract.title
        agreementHTML = AgreementMerge.resolve(
            contract.html,
            with: AgreementMerge.context(
                contact: job.contact ?? pricing.contact,
                job: job,
                studio: studio
            ),
            skipEmptyValues: true
        )
        return true
    }

    /// Merge context for live-fill in the agreement editor — includes draft quote totals / terms.
    func agreementMergeContext(studio: StudioBrand? = nil) -> AgreementMergeContext {
        var ctx = AgreementMerge.context(
            contact: pricing.job?.contact ?? pricing.contact,
            job: pricing.job,
            studio: studio
        )
        let number = issuedNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !number.isEmpty {
            ctx.quoteNumber = number
        }
        ctx.quoteDate = StudioDay.string(pricing.invoiceDate)
        ctx.validUntil = StudioDay.string(validUntil)
        ctx.subtotal = StudioMoney.string(pricing.subtotal)
        ctx.totalAmount = StudioMoney.string(pricing.total)
        ctx.totalTax = StudioMoney.string(pricing.tax)
        ctx.totalDiscount = StudioMoney.string(pricing.discount)
        ctx.remainingBalance = StudioMoney.string(pricing.total)
        ctx.terms = QuotePaymentSchedule.agreementTermsHTML(
            mode: paymentScheduleMode,
            terms: paymentTerms,
            total: pricing.total,
            eventDate: pricing.job?.eventDate
        )
        ctx.quoteDetails = QuoteMath.agreementDetailsHTML(
            lines: pricing.lines,
            tax: pricing.tax,
            discount: pricing.discount,
            shipping: pricing.shipping,
            total: pricing.total
        )
        return ctx
    }

    /// Fills known client / job / studio / quote chips left in the agreement body.
    func fillKnownAgreementFields(studio: StudioBrand? = nil) {
        guard !agreementHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        agreementHTML = AgreementMerge.resolve(
            agreementHTML,
            with: agreementMergeContext(studio: studio),
            skipEmptyValues: true
        )
    }

    func clearAgreement() {
        agreementTitle = ""
        agreementHTML = ""
    }

    func refreshPaymentAmounts() {
        QuotePaymentSchedule.recalculate(&paymentTerms, total: pricing.total)
    }

    func generateScheduledPayments(count: Int, starting: Date) {
        paymentScheduleMode = .scheduled
        paymentTerms = QuotePaymentSchedule.generateScheduled(
            total: pricing.total,
            count: count,
            starting: starting
        )
    }

    func makePreview(studio: StudioBrand?) throws -> QuotePreviewSession {
        let schema = Schema(versionedSchema: StudioSchemaV12.self)
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
        quote.paymentScheduleMode = paymentScheduleMode
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
            let copy = Contact(
                firstName: contact.firstName,
                lastName: contact.lastName,
                fullName: contact.fullName.isEmpty ? contact.displayName : contact.fullName,
                companyName: contact.companyName,
                email: contact.email,
                phone: contact.phone,
                address: contact.address
            )
            context.insert(copy)
            quote.contact = copy
        }
        if let job = pricing.job {
            let copy = Job(
                name: job.name,
                eventDate: job.eventDate,
                jobType: job.jobType,
                status: job.status,
                contact: quote.contact
            )
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
        for (position, term) in paymentTerms.enumerated() {
            let copy = QuotePaymentTerm(
                title: term.title,
                position: position,
                amountMode: term.amountMode,
                percent: term.percent,
                fixedAmount: term.fixedAmount,
                dueMode: term.dueMode,
                daysBeforeEvent: term.daysBeforeEvent,
                fixedDueDate: term.fixedDueDate,
                amount: term.amount
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
        refreshPaymentAmounts()
        if paymentScheduleMode != .none, !paymentScheduleIsComplete {
            throw QuoteDraftError.incompletePaymentSchedule
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
        quote.paymentScheduleMode = paymentScheduleMode
        replaceLines(on: quote, in: context)
        replacePaymentTerms(on: quote, in: context)
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

    private func replacePaymentTerms(on quote: Quote, in context: ModelContext) {
        for term in quote.paymentTerms {
            context.delete(term)
        }
        quote.paymentTerms.removeAll()
        guard paymentScheduleMode != .none else { return }
        for (position, draft) in paymentTerms.enumerated() {
            let term = QuotePaymentTerm(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                position: position,
                amountMode: draft.amountMode,
                percent: draft.percent,
                fixedAmount: draft.fixedAmount,
                dueMode: draft.dueMode,
                daysBeforeEvent: draft.daysBeforeEvent,
                fixedDueDate: draft.fixedDueDate,
                amount: draft.amount
            )
            term.quote = quote
            context.insert(term)
        }
    }
}

enum QuoteDraftError: LocalizedError, Equatable {
    case incompletePaymentSchedule

    var errorDescription: String? {
        switch self {
        case .incompletePaymentSchedule:
            "Payment terms must add up to 100% of the quote total."
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
