import Foundation
import SwiftData

@MainActor
enum BackupExport {
    static func write(
        context: ModelContext,
        scope: BackupScope,
        defaults: UserDefaults,
        to url: URL,
        createdAt: Date = .now
    ) throws -> BackupWriteResult {
        let payload = try payload(context: context, scope: scope, defaults: defaults, createdAt: createdAt)
        try context.save()
        return try BackupPackage.write(payload, to: url)
    }

    static func counts(in context: ModelContext) throws -> BackupManifest.Counts {
        BackupManifest.Counts(
            studios: try context.fetchCount(FetchDescriptor<StudioBrand>()),
            contacts: try context.fetchCount(FetchDescriptor<Contact>()),
            jobs: try context.fetchCount(FetchDescriptor<Job>()),
            catalog: try context.fetchCount(FetchDescriptor<CatalogItem>()),
            taxSchedules: try context.fetchCount(FetchDescriptor<TaxSchedule>()),
            invoices: try context.fetchCount(FetchDescriptor<Invoice>()),
            quotes: try context.fetchCount(FetchDescriptor<Quote>()),
            contracts: try context.fetchCount(FetchDescriptor<Contract>()),
            events: try context.fetchCount(FetchDescriptor<BooksEvent>()),
            quoteEmails: try context.fetchCount(FetchDescriptor<QuoteEmail>()),
            invoiceEmails: try context.fetchCount(FetchDescriptor<InvoiceEmail>()),
            emailTemplates: try context.fetchCount(FetchDescriptor<EmailTemplate>())
        )
    }

    static func payload(
        context: ModelContext,
        scope: BackupScope,
        defaults: UserDefaults,
        createdAt: Date = .now
    ) throws -> BackupPayload {
        let studios = try stamped(FetchDescriptor<StudioBrand>(), in: context)
        let contacts = try stamped(FetchDescriptor<Contact>(), in: context)
        let jobs = try stamped(FetchDescriptor<Job>(), in: context)
        let catalog = try stamped(FetchDescriptor<CatalogItem>(), in: context)
        let taxes = try stamped(FetchDescriptor<TaxSchedule>(), in: context)
        let invoices = try stamped(FetchDescriptor<Invoice>(), in: context)
        let quotes = try stamped(FetchDescriptor<Quote>(), in: context)
        let contracts = try stamped(FetchDescriptor<Contract>(), in: context)
        let events = try stamped(FetchDescriptor<BooksEvent>(), in: context)

        var bodies: [String: Data] = [:]
        var media: [String: Data] = [:]
        let file = BackupFile(
            format: BackupCoding.format,
            scope: scope.rawValue,
            createdAt: createdAt,
            studios: scope.includesBooks ? studios.map { studio($0, media: &media) }.sorted { $0.archiveID < $1.archiveID } : [],
            contacts: scope.includesBooks ? contacts.map(contact).sorted { $0.archiveID < $1.archiveID } : [],
            jobs: scope.includesBooks ? jobs.map(job).sorted { $0.archiveID < $1.archiveID } : [],
            catalog: scope.includesCatalog ? catalog.map(catalogItem).sorted { $0.archiveID < $1.archiveID } : [],
            taxSchedules: scope.includesCatalog ? taxes.map(tax).sorted { $0.archiveID < $1.archiveID } : [],
            invoices: scope.includesBooks ? invoices.map(invoice).sorted { $0.archiveID < $1.archiveID } : [],
            quotes: scope.includesBooks ? quotes.map { quote($0, bodies: &bodies, media: &media) }.sorted { $0.archiveID < $1.archiveID } : [],
            quoteEmails: scope.includesBooks ? try self.quoteEmails(in: context, media: &media) : [],
            invoiceEmails: scope.includesBooks ? try self.invoiceEmails(in: context, media: &media) : [],
            emailTemplates: scope.includesBooks ? try self.emailTemplates(in: context) : [],
            contracts: scope.includesBooks ? contracts.map { contract($0, bodies: &bodies) }.sorted { $0.archiveID < $1.archiveID } : [],
            events: scope.includesBooks ? events.map(event).sorted { $0.archiveID < $1.archiveID } : [],
            preferences: scope.includesPreferences ? BackupPreferenceStore.capture(defaults) : nil
        )
        return BackupPayload(file: file, bodies: bodies, media: media)
    }

    private static func stamped<T: ArchiveStamped>(
        _ descriptor: FetchDescriptor<T>,
        in context: ModelContext
    ) throws -> [T] {
        let records = try context.fetch(descriptor)
        for record in records {
            record.archiveID = BackupIdentity.stored(record.archiveID)
        }
        return records
    }

    private static func studio(_ studio: StudioBrand, media: inout [String: Data]) -> BackupFile.Studio {
        let logo = file(for: studio.logoImageData, media: &media)
        let source = file(for: studio.logoImageSourceData, media: &media)
        return BackupFile.Studio(
            archiveID: studio.archiveID,
            name: studio.name,
            email: studio.email,
            phone: studio.phone,
            address: studio.address,
            isPrimary: studio.isPrimary,
            archived: studio.archived,
            createdAt: studio.createdAt,
            logoFile: logo,
            logoSourceFile: source
        )
    }

    private static func contact(_ contact: Contact) -> BackupFile.Contact {
        BackupFile.Contact(
            archiveID: contact.archiveID,
            shootqID: blank(contact.shootqID),
            firstName: contact.firstName,
            lastName: contact.lastName,
            fullName: contact.fullName,
            companyName: contact.companyName,
            email: contact.email,
            phone: contact.phone,
            address: contact.address,
            anniversary: contact.anniversary,
            archived: contact.archived,
            createdAt: contact.createdAt
        )
    }

    private static func job(_ job: Job) -> BackupFile.Job {
        BackupFile.Job(
            archiveID: job.archiveID,
            shootqID: blank(job.shootqID),
            name: job.name,
            eventDate: job.eventDate,
            jobType: job.jobType,
            status: job.status,
            archived: job.archived,
            contactID: link(job.contact?.archiveID),
            brideID: link(job.bride?.archiveID),
            groomID: link(job.groom?.archiveID),
            paymentScheduleMode: job.paymentScheduleModeRaw,
            paymentTerms: job.sortedPaymentTerms.map { term in
                BackupFile.QuotePaymentTerm(
                    title: term.title,
                    position: term.position,
                    amountMode: term.amountModeRaw,
                    percent: BackupMoney.text(term.percent),
                    fixedAmount: BackupMoney.text(term.fixedAmount),
                    dueMode: term.dueModeRaw,
                    daysBeforeEvent: term.daysBeforeEvent,
                    fixedDueDate: term.fixedDueDate,
                    amount: BackupMoney.text(term.amount)
                )
            }
        )
    }

    private static func quoteEmails(
        in context: ModelContext,
        media: inout [String: Data]
    ) throws -> [BackupFile.QuoteEmail] {
        try context.fetch(FetchDescriptor<QuoteEmail>()).map { email in
            BackupFile.QuoteEmail(
                quoteID: email.quoteKey,
                createdAt: email.createdAt,
                updatedAt: email.updatedAt,
                sentAt: email.sentAt,
                state: email.stateRaw,
                recipient: email.recipient,
                subject: email.subject,
                body: email.body,
                templateName: email.templateName,
                attachAgreement: email.attachAgreement,
                payURL: email.payURL,
                postmarkMessageID: email.postmarkMessageID,
                attachments: attachmentRecords(email.files, media: &media)
            )
        }
        .sorted { lhs, rhs in
            if lhs.quoteID != rhs.quoteID { return lhs.quoteID < rhs.quoteID }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func invoiceEmails(
        in context: ModelContext,
        media: inout [String: Data]
    ) throws -> [BackupFile.InvoiceEmail] {
        try context.fetch(FetchDescriptor<InvoiceEmail>()).map { email in
            BackupFile.InvoiceEmail(
                invoiceID: email.invoiceKey,
                createdAt: email.createdAt,
                updatedAt: email.updatedAt,
                sentAt: email.sentAt,
                state: email.stateRaw,
                recipient: email.recipient,
                subject: email.subject,
                body: email.body,
                templateName: email.templateName,
                payURL: email.payURL,
                postmarkMessageID: email.postmarkMessageID,
                attachments: attachmentRecords(email.files, media: &media)
            )
        }
        .sorted { lhs, rhs in
            if lhs.invoiceID != rhs.invoiceID { return lhs.invoiceID < rhs.invoiceID }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func attachmentRecords(
        _ files: [MailAttachment],
        media: inout [String: Data]
    ) -> [BackupFile.Attachment]? {
        let records = files.sorted { $0.createdAt < $1.createdAt }.compactMap { file -> BackupFile.Attachment? in
            guard let hash = self.file(for: file.bytes, media: &media) else { return nil }
            return BackupFile.Attachment(
                fileName: file.fileName,
                contentType: file.contentType,
                mediaFile: hash
            )
        }
        return records.isEmpty ? nil : records
    }

    private static func emailTemplates(in context: ModelContext) throws -> [BackupFile.EmailTemplate] {
        try context.fetch(FetchDescriptor<EmailTemplate>()).map { template in
            BackupFile.EmailTemplate(
                name: template.name,
                subject: template.subject,
                body: template.body,
                createdAt: template.createdAt,
                updatedAt: template.updatedAt
            )
        }
        .sorted { $0.name < $1.name }
    }

    private static func catalogItem(_ item: CatalogItem) -> BackupFile.CatalogItem {
        BackupFile.CatalogItem(
            archiveID: item.archiveID,
            name: item.name,
            defaultPrice: BackupMoney.text(item.defaultPrice),
            detail: item.detail,
            taxable: item.taxable,
            timesUsed: item.timesUsed
        )
    }

    private static func tax(_ schedule: TaxSchedule) -> BackupFile.TaxSchedule {
        BackupFile.TaxSchedule(
            archiveID: schedule.archiveID,
            name: schedule.name,
            rate: BackupMoney.text(schedule.rate)
        )
    }

    private static func invoice(_ invoice: Invoice) -> BackupFile.Invoice {
        BackupFile.Invoice(
            archiveID: invoice.archiveID,
            shootqID: blank(invoice.shootqID),
            number: invoice.number,
            invoiceDate: invoice.invoiceDate,
            dueDate: invoice.dueDate,
            paidDate: invoice.paidDate,
            status: invoice.statusRaw,
            tax: BackupMoney.text(invoice.tax),
            taxRate: invoice.taxRate.map(BackupMoney.text),
            taxScheduleName: invoice.taxScheduleName,
            invoiceTaxable: invoice.invoiceTaxable,
            discount: BackupMoney.text(invoice.discount),
            shipping: BackupMoney.text(invoice.shipping),
            total: BackupMoney.text(invoice.total),
            amountPaid: BackupMoney.text(invoice.amountPaid),
            balance: BackupMoney.text(invoice.balance),
            collectManually: invoice.collectManually,
            remindersDisabled: invoice.remindersDisabled,
            billToName: invoice.billToName,
            note: invoice.note,
            closing: invoice.closing,
            submittedAt: invoice.submittedAt,
            isImported: invoice.isImported,
            payToken: invoice.payToken.isEmpty ? nil : invoice.payToken,
            contactID: link(invoice.contact?.archiveID),
            jobID: link(invoice.job?.archiveID),
            studioID: link(invoice.studio?.archiveID),
            lines: invoice.sortedLines.map(line),
            schedule: invoice.schedule.map(scheduleEntry).sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) },
            receipts: invoice.receipts.map(receipt).sorted { $0.paidAt < $1.paidAt }
        )
    }

    private static func line(_ line: InvoiceLine) -> BackupFile.Line {
        BackupFile.Line(
            shootqID: blank(line.shootqID),
            name: line.name,
            detail: line.detail,
            quantity: BackupMoney.text(line.quantity),
            unitPrice: BackupMoney.text(line.unitPrice),
            position: line.position,
            packageName: line.packageName,
            taxable: line.taxable,
            catalogID: link(line.catalogItem?.archiveID)
        )
    }

    private static func scheduleEntry(_ entry: PaymentScheduleEntry) -> BackupFile.ScheduleEntry {
        BackupFile.ScheduleEntry(
            shootqID: blank(entry.shootqID),
            due: entry.due,
            amount: BackupMoney.text(entry.amount),
            amountPaid: BackupMoney.text(entry.amountPaid),
            balance: BackupMoney.text(entry.balance),
            status: entry.status
        )
    }

    private static func receipt(_ receipt: PaymentReceipt) -> BackupFile.Receipt {
        BackupFile.Receipt(
            shootqID: blank(receipt.shootqID),
            paidAt: receipt.paidAt,
            amount: BackupMoney.text(receipt.amount),
            method: receipt.methodRaw,
            processorTransactionID: receipt.processorTransactionID.isEmpty ? nil : receipt.processorTransactionID
        )
    }

    private static func quote(
        _ quote: Quote,
        bodies: inout [String: Data],
        media: inout [String: Data]
    ) -> BackupFile.Quote {
        let agreementHash: String?
        if quote.agreementHTML.isEmpty {
            agreementHash = nil
        } else {
            let digest = BackupIdentity.digest(quote.agreementHTML)
            bodies[digest] = Data(quote.agreementHTML.utf8)
            agreementHash = digest
        }
        return BackupFile.Quote(
            archiveID: quote.archiveID,
            number: quote.number,
            quoteDate: quote.quoteDate,
            validUntil: quote.validUntil,
            status: quote.statusRaw,
            tax: BackupMoney.text(quote.tax),
            taxRate: quote.taxRate.map(BackupMoney.text),
            taxScheduleName: quote.taxScheduleName,
            invoiceTaxable: quote.invoiceTaxable,
            discount: BackupMoney.text(quote.discount),
            shipping: BackupMoney.text(quote.shipping),
            total: BackupMoney.text(quote.total),
            billToName: quote.billToName,
            note: quote.note,
            closing: quote.closing,
            agreementTitle: quote.agreementTitle,
            sentAt: quote.sentAt,
            signedAt: quote.signedAt,
            contactID: link(quote.contact?.archiveID),
            jobID: link(quote.job?.archiveID),
            studioID: link(quote.studio?.archiveID),
            invoiceID: link(quote.convertedInvoice?.archiveID),
            agreementBodyFile: agreementHash,
            evidenceFile: file(for: quote.signedEvidenceData, media: &media),
            paymentScheduleMode: quote.paymentScheduleModeRaw,
            paymentTerms: quote.sortedPaymentTerms.map { term in
                BackupFile.QuotePaymentTerm(
                    title: term.title,
                    position: term.position,
                    amountMode: term.amountModeRaw,
                    percent: BackupMoney.text(term.percent),
                    fixedAmount: BackupMoney.text(term.fixedAmount),
                    dueMode: term.dueModeRaw,
                    daysBeforeEvent: term.daysBeforeEvent,
                    fixedDueDate: term.fixedDueDate,
                    amount: BackupMoney.text(term.amount)
                )
            },
            payToken: quote.payToken.isEmpty ? nil : quote.payToken,
            lines: quote.sortedLines.map { line in
                BackupFile.Line(
                    shootqID: nil,
                    name: line.name,
                    detail: line.detail,
                    quantity: BackupMoney.text(line.quantity),
                    unitPrice: BackupMoney.text(line.unitPrice),
                    position: line.position,
                    packageName: "",
                    taxable: line.taxable,
                    catalogID: link(line.catalogItem?.archiveID)
                )
            }
        )
    }

    private static func contract(_ contract: Contract, bodies: inout [String: Data]) -> BackupFile.Contract {
        let html = contract.html
        let hash: String?
        if html.isEmpty {
            hash = nil
        } else {
            let digest = BackupIdentity.digest(html)
            bodies[digest] = Data(html.utf8)
            hash = digest
        }
        return BackupFile.Contract(
            archiveID: contract.archiveID,
            shootqID: blank(contract.shootqID),
            title: contract.title,
            status: contract.status,
            eventLabel: contract.eventLabel,
            sentAt: contract.sentAt,
            isTemplate: contract.isTemplate,
            jobID: link(contract.job?.archiveID),
            bodyFile: hash,
            signatures: contract.signatures.map(signature).sorted { $0.displayName < $1.displayName }
        )
    }

    private static func signature(_ signature: ContractSignature) -> BackupFile.Signature {
        BackupFile.Signature(
            displayName: signature.displayName,
            completed: signature.completed,
            signedAt: signature.signedAt,
            ipAddress: signature.ipAddress,
            shootqContactID: blank(signature.shootqContactID),
            contactID: link(signature.contact?.archiveID)
        )
    }

    private static func event(_ event: BooksEvent) -> BackupFile.BooksEvent {
        BackupFile.BooksEvent(
            archiveID: event.archiveID,
            occurredAt: event.occurredAt,
            kind: event.kindRaw,
            invoiceKey: event.invoiceKey,
            invoiceNumber: event.invoiceNumber,
            clientName: event.clientName,
            amount: BackupMoney.text(event.amount),
            detail: event.detail
        )
    }

    private static func file(for data: Data?, media: inout [String: Data]) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let hash = BackupIdentity.digest(data)
        media[hash] = data
        return hash
    }

    private static func link(_ id: String?) -> String? {
        guard let id else { return nil }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func blank(_ id: String?) -> String? {
        link(id)
    }
}

private protocol ArchiveStamped: PersistentModel {
    var archiveID: String { get set }
}

extension StudioBrand: ArchiveStamped {}
extension Contact: ArchiveStamped {}
extension Job: ArchiveStamped {}
extension CatalogItem: ArchiveStamped {}
extension TaxSchedule: ArchiveStamped {}
extension Invoice: ArchiveStamped {}
extension Quote: ArchiveStamped {}
extension Contract: ArchiveStamped {}
extension BooksEvent: ArchiveStamped {}
