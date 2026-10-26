import Foundation
import SwiftData

/// Loads a backup into the studio. Match order is archive id, then ShootQ id, then one unambiguous natural key.
@MainActor
enum BackupRestore {
    static func apply(
        _ payload: BackupPayload,
        mode: BackupRestoreMode,
        context: ModelContext,
        defaults: UserDefaults
    ) throws -> BackupManifest.Counts {
        guard let scope = BackupScope(rawValue: payload.file.scope) else {
            throw BackupError.unsupportedFormat
        }
        if mode == .replace {
            try delete(scope: scope, context: context)
            try context.save()
        }

        if scope.includesBooks {
            let studios = try upsertStudios(payload.file.studios, media: payload.media, context: context)
            let contacts = try upsertContacts(payload.file.contacts, context: context)
            let catalog = try upsertCatalog(payload.file.catalog, scope: scope, context: context)
            try upsertTaxes(payload.file.taxSchedules, scope: scope, context: context)
            let jobs = try upsertJobs(payload.file.jobs, contacts: contacts, context: context)
            let invoices = try upsertInvoices(
                payload.file.invoices,
                contacts: contacts,
                jobs: jobs,
                studios: studios.index,
                context: context
            )
            let contracts = try upsertContracts(
                payload.file.contracts,
                jobs: jobs,
                bodies: payload.bodies,
                context: context
            )
            try upsertEvents(payload.file.events, context: context)
            stripChildren(invoices: invoices, contracts: contracts, context: context)
            try context.save()
            try addInvoiceChildren(invoices, catalog: catalog, context: context)
            addSignatures(contracts, contacts: contacts, context: context)
            if !studios.primary.isEmpty {
                try enforcePrimary(studios.primary, context: context)
            }
        } else {
            _ = try upsertCatalog(payload.file.catalog, scope: scope, context: context)
            try upsertTaxes(payload.file.taxSchedules, scope: scope, context: context)
            if mode == .replace {
                try relinkLinesByName(context)
            }
        }

        if let preferences = payload.file.preferences, scope.includesPreferences {
            switch mode {
            case .replace:
                BackupPreferenceStore.replace(preferences, in: defaults)
            case .merge:
                BackupPreferenceStore.merge(preferences, in: defaults)
            }
        }
        try context.save()
        return payload.file.counts
    }

    // MARK: - Delete

    private static func delete(scope: BackupScope, context: ModelContext) throws {
        if scope.includesBooks {
            try wipe(BooksEvent.self, context)
            try wipe(Contract.self, context)
            try wipe(Invoice.self, context)
            try wipe(Job.self, context)
            try wipe(Contact.self, context)
            try wipe(StudioBrand.self, context)
        }
        if scope.includesCatalog {
            try wipe(CatalogItem.self, context)
            try wipe(TaxSchedule.self, context)
        }
    }

    private static func wipe<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<T>()) {
            context.delete(item)
        }
    }

    // MARK: - Studios

    private struct StudioResult {
        var index: BackupIndex<StudioBrand>
        var primary: [StudioBrand]
    }

    private static func upsertStudios(
        _ records: [BackupFile.Studio],
        media: [String: Data],
        context: ModelContext
    ) throws -> StudioResult {
        let locals = try context.fetch(FetchDescriptor<StudioBrand>())
        var index = BackupIndex<StudioBrand>()
        for studio in locals {
            index.register(archiveID: studio.archiveID, shootqID: nil, model: studio)
        }
        var primary: [StudioBrand] = []
        for record in records {
            let studio: StudioBrand
            let existed: Bool
            if let found = index.existing(archiveID: record.archiveID, shootqID: nil) {
                studio = found
                existed = true
            } else if let found = unique(locals.filter {
                !$0.name.isEmpty && $0.name.caseInsensitiveCompare(record.name) == .orderedSame && !index.isUsed($0)
            }) {
                studio = found
                existed = true
            } else {
                studio = StudioBrand()
                studio.archiveID = BackupIdentity.stored(record.archiveID)
                context.insert(studio)
                existed = false
            }
            index.markUsed(studio)
            apply(record, to: studio, media: media, existed: existed)
            adopt(
                fileArchiveID: record.archiveID,
                fileShootQID: nil,
                localArchiveID: &studio.archiveID,
                localShootQID: nil,
                model: studio,
                index: &index
            )
            if record.isPrimary { primary.append(studio) }
        }
        return StudioResult(index: index, primary: primary)
    }

    private static func apply(_ record: BackupFile.Studio, to studio: StudioBrand, media: [String: Data], existed: Bool) {
        studio.name = record.name
        studio.email = record.email
        studio.phone = record.phone
        studio.address = record.address
        studio.isPrimary = record.isPrimary
        studio.archived = record.archived
        studio.createdAt = record.createdAt
        studio.logoImageData = bytes(record.logoFile, media: media, existed: existed, current: studio.logoImageData)
        studio.logoImageSourceData = bytes(record.logoSourceFile, media: media, existed: existed, current: studio.logoImageSourceData)
    }

    private static func bytes(_ hash: String?, media: [String: Data], existed: Bool, current: Data?) -> Data? {
        guard let hash else { return nil }
        if let data = media[hash] { return data }
        return existed ? current : nil
    }

    // MARK: - Contacts

    private static func upsertContacts(_ records: [BackupFile.Contact], context: ModelContext) throws -> BackupIndex<Contact> {
        let locals = try context.fetch(FetchDescriptor<Contact>())
        var index = BackupIndex<Contact>()
        for contact in locals {
            index.register(archiveID: contact.archiveID, shootqID: contact.shootqID, model: contact)
        }
        for record in records {
            let contact: Contact
            if let found = index.existing(archiveID: record.archiveID, shootqID: record.shootqID) {
                contact = found
            } else if let found = naturalContact(record, locals: locals, index: index) {
                contact = found
            } else {
                contact = Contact()
                contact.archiveID = BackupIdentity.stored(record.archiveID)
                context.insert(contact)
            }
            index.markUsed(contact)
            apply(record, to: contact)
            adopt(
                fileArchiveID: record.archiveID,
                fileShootQID: record.shootqID,
                localArchiveID: &contact.archiveID,
                localShootQID: contact.shootqID,
                model: contact,
                index: &index
            )
        }
        return index
    }

    private static func naturalContact(_ record: BackupFile.Contact, locals: [Contact], index: BackupIndex<Contact>) -> Contact? {
        let email = record.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty {
            let matches = locals.filter {
                $0.email.caseInsensitiveCompare(email) == .orderedSame && !index.isUsed($0)
            }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { return nil }
        }
        let name = record.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return unique(locals.filter {
            $0.fullName.caseInsensitiveCompare(name) == .orderedSame && !index.isUsed($0)
        })
    }

    private static func apply(_ record: BackupFile.Contact, to contact: Contact) {
        contact.shootqID = record.shootqID
        contact.firstName = record.firstName
        contact.lastName = record.lastName
        contact.fullName = record.fullName
        contact.companyName = record.companyName
        contact.email = record.email
        contact.phone = record.phone
        contact.address = record.address
        contact.anniversary = record.anniversary
        contact.archived = record.archived
        contact.createdAt = record.createdAt
    }

    // MARK: - Catalog and tax

    private static func upsertCatalog(
        _ records: [BackupFile.CatalogItem],
        scope: BackupScope,
        context: ModelContext
    ) throws -> BackupIndex<CatalogItem> {
        let locals = try context.fetch(FetchDescriptor<CatalogItem>())
        var index = BackupIndex<CatalogItem>()
        for item in locals {
            index.register(archiveID: item.archiveID, shootqID: nil, model: item)
        }
        guard scope.includesCatalog else { return index }
        for record in records {
            let item: CatalogItem
            if let found = index.existing(archiveID: record.archiveID, shootqID: nil) {
                item = found
            } else if let found = unique(locals.filter { $0.name == record.name && !index.isUsed($0) }) {
                item = found
            } else {
                item = CatalogItem(
                    name: record.name,
                    defaultPrice: try BackupMoney.decimal(record.defaultPrice),
                    detail: record.detail,
                    taxable: record.taxable ?? false,
                    timesUsed: record.timesUsed
                )
                item.taxable = record.taxable
                item.archiveID = BackupIdentity.stored(record.archiveID)
                context.insert(item)
            }
            index.markUsed(item)
            item.name = record.name
            item.defaultPrice = try BackupMoney.decimal(record.defaultPrice)
            item.detail = record.detail
            item.taxable = record.taxable
            item.timesUsed = record.timesUsed
            adopt(
                fileArchiveID: record.archiveID,
                fileShootQID: nil,
                localArchiveID: &item.archiveID,
                localShootQID: nil,
                model: item,
                index: &index
            )
        }
        return index
    }

    private static func upsertTaxes(
        _ records: [BackupFile.TaxSchedule],
        scope: BackupScope,
        context: ModelContext
    ) throws {
        guard scope.includesCatalog else { return }
        let locals = try context.fetch(FetchDescriptor<TaxSchedule>())
        var index = BackupIndex<TaxSchedule>()
        for schedule in locals {
            index.register(archiveID: schedule.archiveID, shootqID: nil, model: schedule)
        }
        for record in records {
            let schedule: TaxSchedule
            if let found = index.existing(archiveID: record.archiveID, shootqID: nil) {
                schedule = found
            } else if let found = unique(locals.filter { $0.name == record.name && !index.isUsed($0) }) {
                schedule = found
            } else {
                schedule = TaxSchedule(name: record.name, rate: try BackupMoney.decimal(record.rate))
                schedule.archiveID = BackupIdentity.stored(record.archiveID)
                context.insert(schedule)
            }
            index.markUsed(schedule)
            schedule.name = record.name
            schedule.rate = try BackupMoney.decimal(record.rate)
            adopt(
                fileArchiveID: record.archiveID,
                fileShootQID: nil,
                localArchiveID: &schedule.archiveID,
                localShootQID: nil,
                model: schedule,
                index: &index
            )
        }
    }

    private static func relinkLinesByName(_ context: ModelContext) throws {
        let catalog = try context.fetch(FetchDescriptor<CatalogItem>())
        let grouped = Dictionary(grouping: catalog, by: \.name)
        for line in try context.fetch(FetchDescriptor<InvoiceLine>()) where line.catalogItem == nil {
            let matches = grouped[line.name] ?? []
            if matches.count == 1 {
                line.catalogItem = matches[0]
            }
        }
    }

    // MARK: - Jobs, invoices, contracts, events

    private static func upsertJobs(
        _ records: [BackupFile.Job],
        contacts: BackupIndex<Contact>,
        context: ModelContext
    ) throws -> BackupIndex<Job> {
        let locals = try context.fetch(FetchDescriptor<Job>())
        var index = BackupIndex<Job>()
        for job in locals {
            index.register(archiveID: job.archiveID, shootqID: job.shootqID, model: job)
        }
        for record in records {
            let job: Job
            if let found = index.existing(archiveID: record.archiveID, shootqID: record.shootqID) {
                job = found
            } else if let found = naturalJob(record, locals: locals, index: index) {
                job = found
            } else {
                job = Job()
                job.archiveID = BackupIdentity.stored(record.archiveID)
                context.insert(job)
            }
            index.markUsed(job)
            job.shootqID = record.shootqID
            job.name = record.name
            job.eventDate = record.eventDate
            job.jobType = record.jobType
            job.status = record.status
            job.archived = record.archived
            job.contact = record.contactID.flatMap { contacts.existing(archiveID: $0, shootqID: nil) }
            adopt(
                fileArchiveID: record.archiveID,
                fileShootQID: record.shootqID,
                localArchiveID: &job.archiveID,
                localShootQID: job.shootqID,
                model: job,
                index: &index
            )
        }
        return index
    }

    private static func naturalJob(_ record: BackupFile.Job, locals: [Job], index: BackupIndex<Job>) -> Job? {
        let name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return unique(locals.filter {
            $0.name.caseInsensitiveCompare(name) == .orderedSame && sameDay($0.eventDate, record.eventDate) && !index.isUsed($0)
        })
    }

    private static func upsertInvoices(
        _ records: [BackupFile.Invoice],
        contacts: BackupIndex<Contact>,
        jobs: BackupIndex<Job>,
        studios: BackupIndex<StudioBrand>,
        context: ModelContext
    ) throws -> [PendingInvoice] {
        let locals = try context.fetch(FetchDescriptor<Invoice>())
        var index = BackupIndex<Invoice>()
        for invoice in locals {
            index.register(archiveID: invoice.archiveID, shootqID: invoice.shootqID, model: invoice)
        }
        var pending: [PendingInvoice] = []
        for record in records {
            let invoice: Invoice
            if let found = index.existing(archiveID: record.archiveID, shootqID: record.shootqID) {
                invoice = found
            } else if let found = naturalInvoice(record, locals: locals, index: index) {
                invoice = found
            } else {
                invoice = Invoice()
                invoice.archiveID = BackupIdentity.stored(record.archiveID)
                context.insert(invoice)
            }
            index.markUsed(invoice)
            try apply(record, to: invoice, contacts: contacts, jobs: jobs, studios: studios)
            adopt(
                fileArchiveID: record.archiveID,
                fileShootQID: record.shootqID,
                localArchiveID: &invoice.archiveID,
                localShootQID: invoice.shootqID,
                model: invoice,
                index: &index
            )
            pending.append(PendingInvoice(invoice: invoice, record: record))
        }
        return pending
    }

    private static func naturalInvoice(
        _ record: BackupFile.Invoice,
        locals: [Invoice],
        index: BackupIndex<Invoice>
    ) -> Invoice? {
        let number = record.number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else { return nil }
        return unique(locals.filter { $0.number == number && !index.isUsed($0) })
    }

    private static func apply(
        _ record: BackupFile.Invoice,
        to invoice: Invoice,
        contacts: BackupIndex<Contact>,
        jobs: BackupIndex<Job>,
        studios: BackupIndex<StudioBrand>
    ) throws {
        invoice.shootqID = record.shootqID
        invoice.number = record.number
        invoice.invoiceDate = record.invoiceDate
        invoice.dueDate = record.dueDate
        invoice.paidDate = record.paidDate
        invoice.statusRaw = record.status
        invoice.tax = try BackupMoney.decimal(record.tax)
        invoice.taxRate = try BackupMoney.optional(record.taxRate)
        invoice.taxScheduleName = record.taxScheduleName
        invoice.invoiceTaxable = record.invoiceTaxable
        invoice.discount = try BackupMoney.decimal(record.discount)
        invoice.shipping = try BackupMoney.decimal(record.shipping)
        invoice.total = try BackupMoney.decimal(record.total)
        invoice.amountPaid = try BackupMoney.decimal(record.amountPaid)
        invoice.balance = try BackupMoney.decimal(record.balance)
        invoice.collectManually = record.collectManually
        invoice.remindersDisabled = record.remindersDisabled
        invoice.billToName = record.billToName
        invoice.note = record.note
        invoice.closing = record.closing
        invoice.submittedAt = record.submittedAt
        invoice.isImported = record.isImported
        invoice.contact = record.contactID.flatMap { contacts.existing(archiveID: $0, shootqID: nil) }
        invoice.job = record.jobID.flatMap { jobs.existing(archiveID: $0, shootqID: nil) }
        invoice.studio = record.studioID.flatMap { studios.existing(archiveID: $0, shootqID: nil) }
    }

    private static func upsertContracts(
        _ records: [BackupFile.Contract],
        jobs: BackupIndex<Job>,
        bodies: [String: Data],
        context: ModelContext
    ) throws -> [PendingContract] {
        let locals = try context.fetch(FetchDescriptor<Contract>())
        var index = BackupIndex<Contract>()
        for contract in locals {
            index.register(archiveID: contract.archiveID, shootqID: contract.shootqID, model: contract)
        }
        var pending: [PendingContract] = []
        for record in records {
            let contract: Contract
            let existed: Bool
            if let found = index.existing(archiveID: record.archiveID, shootqID: record.shootqID) {
                contract = found
                existed = true
            } else {
                contract = Contract()
                contract.archiveID = BackupIdentity.stored(record.archiveID)
                context.insert(contract)
                existed = false
            }
            index.markUsed(contract)
            contract.shootqID = record.shootqID
            contract.title = record.title
            contract.status = record.status
            contract.eventLabel = record.eventLabel
            contract.sentAt = record.sentAt
            contract.job = record.jobID.flatMap { jobs.existing(archiveID: $0, shootqID: nil) }
            if let hash = record.bodyFile, let data = bodies[hash] {
                contract.html = String(decoding: data, as: UTF8.self)
            } else if !existed {
                contract.html = ""
            }
            adopt(
                fileArchiveID: record.archiveID,
                fileShootQID: record.shootqID,
                localArchiveID: &contract.archiveID,
                localShootQID: contract.shootqID,
                model: contract,
                index: &index
            )
            pending.append(PendingContract(contract: contract, record: record))
        }
        return pending
    }

    private static func upsertEvents(_ records: [BackupFile.BooksEvent], context: ModelContext) throws {
        let locals = try context.fetch(FetchDescriptor<BooksEvent>())
        var index = BackupIndex<BooksEvent>()
        var fingerprints: [String: [BooksEvent]] = [:]
        for event in locals {
            index.register(archiveID: event.archiveID, shootqID: nil, model: event)
            fingerprints[fingerprint(event), default: []].append(event)
        }
        for record in records {
            let event: BooksEvent
            let key = try fingerprint(record)
            if let found = index.existing(archiveID: record.archiveID, shootqID: nil) {
                event = found
            } else if let found = unique((fingerprints[key] ?? []).filter { !index.isUsed($0) }) {
                event = found
            } else {
                event = BooksEvent(
                    occurredAt: record.occurredAt,
                    kind: BooksEventKind(rawValue: record.kind) ?? .edited,
                    invoiceKey: record.invoiceKey,
                    invoiceNumber: record.invoiceNumber,
                    clientName: record.clientName,
                    amount: try BackupMoney.decimal(record.amount),
                    detail: record.detail
                )
                event.archiveID = BackupIdentity.stored(record.archiveID)
                context.insert(event)
            }
            index.markUsed(event)
            event.occurredAt = record.occurredAt
            event.kindRaw = record.kind
            event.invoiceKey = record.invoiceKey
            event.invoiceNumber = record.invoiceNumber
            event.clientName = record.clientName
            event.amount = try BackupMoney.decimal(record.amount)
            event.detail = record.detail
            adopt(
                fileArchiveID: record.archiveID,
                fileShootQID: nil,
                localArchiveID: &event.archiveID,
                localShootQID: nil,
                model: event,
                index: &index
            )
        }
    }

    // MARK: - Owned children

    private struct PendingInvoice {
        var invoice: Invoice
        var record: BackupFile.Invoice
    }

    private struct PendingContract {
        var contract: Contract
        var record: BackupFile.Contract
    }

    private static func stripChildren(
        invoices: [PendingInvoice],
        contracts: [PendingContract],
        context: ModelContext
    ) {
        for item in invoices {
            Array(item.invoice.lines).forEach(context.delete)
            Array(item.invoice.receipts).forEach(context.delete)
            Array(item.invoice.schedule).forEach(context.delete)
        }
        for item in contracts {
            Array(item.contract.signatures).forEach(context.delete)
        }
    }

    private static func addInvoiceChildren(
        _ pending: [PendingInvoice],
        catalog: BackupIndex<CatalogItem>,
        context: ModelContext
    ) throws {
        for item in pending {
            for record in item.record.lines {
                let line = InvoiceLine(
                    shootqID: record.shootqID,
                    name: record.name,
                    detail: record.detail,
                    quantity: try BackupMoney.decimal(record.quantity),
                    unitPrice: try BackupMoney.decimal(record.unitPrice),
                    position: record.position,
                    packageName: record.packageName,
                    taxable: record.taxable ?? false
                )
                line.taxable = record.taxable
                line.invoice = item.invoice
                if let catalogID = record.catalogID {
                    line.catalogItem = catalog.existing(archiveID: catalogID, shootqID: nil)
                }
                context.insert(line)
            }
            for record in item.record.schedule {
                let entry = PaymentScheduleEntry(
                    shootqID: record.shootqID,
                    due: record.due,
                    amount: try BackupMoney.decimal(record.amount),
                    amountPaid: try BackupMoney.decimal(record.amountPaid),
                    balance: try BackupMoney.decimal(record.balance),
                    status: record.status
                )
                entry.invoice = item.invoice
                context.insert(entry)
            }
            for record in item.record.receipts {
                let receipt = PaymentReceipt(
                    shootqID: record.shootqID,
                    paidAt: record.paidAt,
                    amount: try BackupMoney.decimal(record.amount),
                    method: PaymentMethod(rawValue: record.method) ?? .other
                )
                receipt.methodRaw = record.method
                receipt.invoice = item.invoice
                context.insert(receipt)
            }
        }
    }

    private static func addSignatures(
        _ pending: [PendingContract],
        contacts: BackupIndex<Contact>,
        context: ModelContext
    ) {
        for item in pending {
            for record in item.record.signatures {
                let signature = ContractSignature(
                    displayName: record.displayName,
                    completed: record.completed,
                    signedAt: record.signedAt,
                    ipAddress: record.ipAddress,
                    shootqContactID: record.shootqContactID
                )
                if let contactID = record.contactID {
                    signature.contact = contacts.existing(archiveID: contactID, shootqID: nil)
                }
                if signature.contact == nil, let shootq = record.shootqContactID {
                    signature.contact = contacts.existing(archiveID: "", shootqID: shootq)
                }
                signature.contract = item.contract
                context.insert(signature)
            }
        }
    }

    private static func enforcePrimary(_ primary: [StudioBrand], context: ModelContext) throws {
        let studios = try context.fetch(FetchDescriptor<StudioBrand>())
        for studio in studios {
            studio.isPrimary = primary.contains { $0 === studio }
        }
    }

    // MARK: - Matching

    private static func adopt<Model: AnyObject>(
        fileArchiveID: String,
        fileShootQID: String?,
        localArchiveID: inout String,
        localShootQID: String?,
        model: Model,
        index: inout BackupIndex<Model>
    ) {
        if localArchiveID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let incoming = fileArchiveID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !incoming.isEmpty { localArchiveID = incoming }
        }
        index.register(archiveID: fileArchiveID, shootqID: fileShootQID, model: model)
        index.register(archiveID: localArchiveID, shootqID: localShootQID, model: model)
    }

    private static func unique<Model: AnyObject>(_ models: [Model]) -> Model? {
        models.count == 1 ? models[0] : nil
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

    private static func fingerprint(_ event: BooksEvent) -> String {
        joinedFingerprint(
            invoiceKey: event.invoiceKey,
            occurredAt: event.occurredAt,
            kind: event.kindRaw,
            invoiceNumber: event.invoiceNumber,
            clientName: event.clientName,
            amount: BackupMoney.text(event.amount),
            detail: event.detail
        )
    }

    private static func fingerprint(_ record: BackupFile.BooksEvent) throws -> String {
        joinedFingerprint(
            invoiceKey: record.invoiceKey,
            occurredAt: record.occurredAt,
            kind: record.kind,
            invoiceNumber: record.invoiceNumber,
            clientName: record.clientName,
            amount: BackupMoney.text(try BackupMoney.decimal(record.amount)),
            detail: record.detail
        )
    }

    private static func joinedFingerprint(
        invoiceKey: String,
        occurredAt: Date,
        kind: String,
        invoiceNumber: String,
        clientName: String,
        amount: String,
        detail: String
    ) -> String {
        let second = String(Int(occurredAt.timeIntervalSince1970.rounded()))
        return [invoiceKey, second, kind, invoiceNumber, clientName, amount, detail].joined(separator: "\u{1e}")
    }
}

private struct BackupIndex<Model: AnyObject> {
    private var byArchive: [String: Model] = [:]
    private var byShootQ: [String: Model] = [:]
    private var used = Set<ObjectIdentifier>()

    mutating func register(archiveID: String, shootqID: String?, model: Model) {
        let archive = archiveID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !archive.isEmpty { byArchive[archive] = model }
        let shootq = shootqID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !shootq.isEmpty { byShootQ[shootq] = model }
    }

    func existing(archiveID: String, shootqID: String?) -> Model? {
        let archive = archiveID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !archive.isEmpty, let model = byArchive[archive] { return model }
        let shootq = shootqID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !shootq.isEmpty, let model = byShootQ[shootq] { return model }
        return nil
    }

    mutating func markUsed(_ model: Model) {
        used.insert(ObjectIdentifier(model))
    }

    func isUsed(_ model: Model) -> Bool {
        used.contains(ObjectIdentifier(model))
    }
}
