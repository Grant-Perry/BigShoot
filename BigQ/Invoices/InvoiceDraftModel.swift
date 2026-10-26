import Foundation
import SwiftData

struct DraftLine: Identifiable {
    let id = UUID()
    var name: String
    var detail: String
    var quantity: Decimal
    var unitPrice: Decimal
    /// Copied from the catalog at the moment the line is added.
    var taxable: Bool
    var catalogItem: CatalogItem?

    var lineTotal: Decimal {
        InvoiceMath.lineTotal(quantity: quantity, unitPrice: unitPrice)
    }
}

@MainActor
@Observable
final class InvoiceDraftModel {
    static let defaultNetDays = 45

    var contact: Contact?
    var job: Job?
    var invoiceDate = Date.now
    /// Days after the shoot (or the invoice date, when the job has no shoot date) that payment is due.
    var netDays = InvoiceDraftModel.defaultNetDays
    var dueDate = InvoiceDraftModel.date(daysAfter: .now, netDays: InvoiceDraftModel.defaultNetDays)
    /// Dollar tax already stored on the invoice. Used until a rate is applied.
    private var storedTax: Decimal = 0
    /// True once a rate is driving the dollar tax. Imported flat tax stays put until then.
    var calculatesTax = false
    /// Master switch. Off keeps the rate on screen and adds no tax to the balance.
    var invoiceTaxable = false
    /// Fraction, such as 0.066 for 6.6%.
    var taxRate: Decimal = 0
    var taxRateText = ""
    var taxScheduleName = ""
    var discount: Decimal = 0
    var shipping: Decimal = 0
    var note = ""
    var closing = ""
    var submittedAt: Date?
    /// Already on the books when the editor opened. Nil on a new invoice.
    private(set) var pipelineSubmittedAt: Date?
    var lines: [DraftLine] = []
    /// Kept so a preview can show the number and payments already on a saved invoice.
    var issuedNumber = ""
    private var issuedShootqID: String?
    /// Job name last copied into a blank note. Replaced on a later job change only while the note still matches.
    private var noteCarriedFromJob: String?
    var amountPaid: Decimal = 0
    var paidDate: Date?
    private var editingID: PersistentIdentifier?
    private var editingStatus: InvoiceStatus?

    var subtotal: Decimal {
        lines.reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    var taxableSubtotal: Decimal {
        lines.reduce(Decimal.zero) { partial, line in
            line.taxable ? partial + line.lineTotal : partial
        }
    }

    var tax: Decimal {
        guard invoiceTaxable else { return 0 }
        if calculatesTax {
            return TaxRateInput.amount(taxableSubtotal: taxableSubtotal, rate: taxRate)
        }
        return storedTax
    }

    var total: Decimal {
        InvoiceMath.total(subtotal: subtotal, tax: tax, discount: discount, shipping: shipping)
    }

    var canSave: Bool {
        contact != nil && lines.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// A taxed line needs a rate. Charge Tax with nothing marked taxable can still save.
    var isMissingTaxRate: Bool {
        guard lines.contains(where: \.taxable) else { return false }
        let typed = TaxRateInput.fraction(from: taxRateText) ?? 0
        return taxRate <= 0 && typed <= 0
    }

    var isEditing: Bool { editingID != nil }

    /// Number shown beside “Edit invoice”. Blank on a new invoice and on a draft that has no number yet.
    var titleNumber: String {
        let trimmed = issuedNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return issuedShootqID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// A sent invoice keeps its status. Save does not turn it back into a draft.
    var editingSentInvoice: Bool {
        guard let editingStatus else { return false }
        return editingStatus != .draft
    }

    func load(_ invoice: Invoice) {
        editingID = invoice.persistentModelID
        editingStatus = invoice.status
        contact = invoice.contact
        job = invoice.job
        invoiceDate = invoice.invoiceDate
        dueDate = invoice.dueDate ?? invoiceDate
        syncNetDaysFromDueDate()
        storedTax = invoice.tax
        taxRate = invoice.taxRate ?? 0
        taxScheduleName = invoice.taxScheduleName ?? ""
        calculatesTax = taxRate > 0
        invoiceTaxable = invoice.appliesTax
        taxRateText = calculatesTax ? TaxRateInput.percentText(for: taxRate) : ""
        discount = invoice.discount
        shipping = invoice.shipping
        note = invoice.note
        closing = invoice.closing
        submittedAt = invoice.submittedAt
        pipelineSubmittedAt = invoice.submittedAt
        issuedNumber = invoice.number
        issuedShootqID = invoice.shootqID
        amountPaid = invoice.amountPaid
        paidDate = invoice.paidDate
        lines = invoice.sortedLines.map { line in
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

    /// A blank note prints the job name. A note the user has typed is left alone.
    func fillEmptyNoteFromJob() {
        let jobName = job?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let current = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let stillDefault = current.isEmpty || (noteCarriedFromJob != nil && current == noteCarriedFromJob)
        guard stillDefault, !jobName.isEmpty else { return }
        note = jobName
        noteCarriedFromJob = jobName
    }

    /// Copies the catalog row onto this invoice. Later catalog edits do not change the copy.
    func addCatalogItem(_ item: CatalogItem) {
        lines.append(DraftLine(
            name: item.name,
            detail: item.detail,
            quantity: 1,
            unitPrice: item.defaultPrice,
            taxable: item.taxable ?? false,
            catalogItem: item
        ))
    }

    func addBlankLine() {
        lines.append(DraftLine(name: "", detail: "", quantity: 1, unitPrice: 0, taxable: false, catalogItem: nil))
    }

    /// Submit pressed. The stamp is in the pipeline, so a later save has to confirm.
    func noteSubmitted(_ date: Date = .now) {
        submittedAt = date
        pipelineSubmittedAt = date
    }

    func removeLine(id: UUID) {
        lines.removeAll { $0.id == id }
    }

    /// A throwaway invoice in its own store, so preview never writes the books.
    func makePreview(studio: StudioBrand?) throws -> InvoicePreviewSession {
        let schema = Schema(versionedSchema: StudioSchemaV9.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let invoice = Invoice(
            number: issuedNumber,
            invoiceDate: invoiceDate,
            dueDate: dueDate,
            paidDate: paidDate,
            status: .draft,
            tax: tax,
            discount: discount,
            shipping: shipping,
            amountPaid: amountPaid,
            billToName: contact?.displayName ?? "",
            note: note,
            closing: closing
        )
        context.insert(invoice)
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
            invoice.studio = copy
        }
        if let contact {
            let copy = Contact(fullName: contact.displayName, email: contact.email)
            context.insert(copy)
            invoice.contact = copy
        }
        if let job {
            let copy = Job(name: job.name, eventDate: job.eventDate, jobType: job.jobType)
            context.insert(copy)
            invoice.job = copy
        }
        for (position, line) in lines.enumerated() {
            let copy = InvoiceLine(
                name: line.name,
                detail: line.detail,
                quantity: line.quantity,
                unitPrice: line.unitPrice,
                position: position,
                taxable: line.taxable
            )
            copy.invoice = invoice
            context.insert(copy)
        }
        InvoiceMath.recalculate(invoice)
        return InvoicePreviewSession(container: container, context: context, invoice: invoice)
    }

    func apply(schedule: TaxSchedule) {
        taxScheduleName = schedule.name
        taxRate = schedule.rate
        taxRateText = TaxRateInput.percentText(for: schedule.rate)
        calculatesTax = true
    }

    func clearScheduleSelection() {
        taxScheduleName = ""
    }

    /// Reads the rate field. `6.6` and `0.066` both become a 6.6% rate. A blank field leaves a stored flat tax alone.
    func commitTaxRate(schedules: [TaxSchedule]) {
        let parsed = TaxRateInput.fraction(from: taxRateText) ?? 0
        if !calculatesTax && parsed == 0 {
            taxRateText = ""
            return
        }
        taxRate = parsed
        taxRateText = TaxRateInput.percentText(for: parsed)
        calculatesTax = true
        if schedules.first(where: { $0.name == taxScheduleName })?.rate != parsed {
            taxScheduleName = ""
        }
    }

    /// Due date follows net days. The shoot date is the anchor; the invoice date stands in until a shoot date exists.
    func applyNetDays() {
        let next = Self.date(daysAfter: paymentAnchor, netDays: netDays)
        guard !Calendar.current.isDate(dueDate, inSameDayAs: next) else { return }
        dueDate = next
    }

    /// Keeps the net field honest when the due date is picked directly.
    func syncNetDaysFromDueDate() {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: paymentAnchor),
            to: calendar.startOfDay(for: dueDate)
        ).day ?? netDays
        guard days != netDays else { return }
        netDays = days
    }

    private var paymentAnchor: Date {
        job?.eventDate ?? invoiceDate
    }

    private static func date(daysAfter anchor: Date, netDays: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: anchor)
        return calendar.date(byAdding: .day, value: netDays, to: start) ?? start
    }

    func save(in context: ModelContext, markSent: Bool) throws -> Invoice {
        if isMissingTaxRate {
            invoiceTaxable = true
            throw InvoiceDraftError.missingTaxRate
        }
        let creating = editingID == nil
        let invoice = try preparedInvoice(in: context)
        let beforeEdit = creating ? nil : BooksTrail.EditSnapshot(invoice)
        let wasDraft = invoice.status == .draft
        invoice.contact = contact
        invoice.job = job
        invoice.invoiceDate = invoiceDate
        invoice.dueDate = dueDate
        invoice.tax = tax
        invoice.taxRate = calculatesTax ? taxRate : 0
        invoice.taxScheduleName = calculatesTax ? taxScheduleName : ""
        invoice.invoiceTaxable = invoiceTaxable
        invoice.discount = discount
        invoice.shipping = shipping
        invoice.note = note
        invoice.closing = closing
        invoice.submittedAt = submittedAt
        invoice.billToName = contact?.displayName ?? invoice.billToName
        replaceLines(on: invoice, in: context)
        if markSent {
            if invoice.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let numbers = try context.fetch(FetchDescriptor<Invoice>()).map(\.number)
                invoice.number = InvoiceMath.nextNumber(among: numbers)
            }
            if invoice.status == .draft {
                invoice.status = .pending
            }
        }
        InvoiceMath.recalculate(invoice)
        if markSent && (creating || wasDraft) {
            BooksTrail.noteMarkedSent(invoice, in: context)
        } else if creating {
            BooksTrail.noteCreated(invoice, in: context)
        } else if let beforeEdit {
            BooksTrail.noteEdited(invoice, before: beforeEdit, in: context)
        }
        if creating, invoice.submittedAt != nil {
            BooksTrail.noteSubmitted(invoice, in: context)
        }
        try context.save()
        return invoice
    }

    private func preparedInvoice(in context: ModelContext) throws -> Invoice {
        if let editingID, let existing = context.model(for: editingID) as? Invoice {
            return existing
        }
        let invoice = Invoice(status: .draft, isImported: false)
        context.insert(invoice)
        invoice.studio = try StudioBrandDirectory.primary(in: context)
        return invoice
    }

    private func replaceLines(on invoice: Invoice, in context: ModelContext) {
        for line in invoice.lines {
            if let item = line.catalogItem {
                item.timesUsed = max(0, item.timesUsed - 1)
            }
            context.delete(line)
        }
        invoice.lines.removeAll()
        let named = lines.enumerated().filter {
            !$0.element.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for (position, draft) in named {
            let line = InvoiceLine(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                detail: draft.detail,
                quantity: draft.quantity,
                unitPrice: draft.unitPrice,
                position: position,
                taxable: draft.taxable
            )
            line.invoice = invoice
            line.catalogItem = draft.catalogItem
            draft.catalogItem?.timesUsed += 1
            context.insert(line)
        }
    }
}

enum InvoiceDraftError: LocalizedError, Equatable {
    case missingTaxRate

    var errorDescription: String? {
        switch self {
        case .missingTaxRate:
            "Choose a tax rate."
        }
    }
}
