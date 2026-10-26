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
            contracts: try context.fetchCount(FetchDescriptor<Contract>()),
            events: try context.fetchCount(FetchDescriptor<BooksEvent>())
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
            contactID: link(job.contact?.archiveID)
        )
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
            method: receipt.methodRaw
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
extension Contract: ArchiveStamped {}
extension BooksEvent: ArchiveStamped {}
