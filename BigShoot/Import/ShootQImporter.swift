import Foundation
import SwiftData

struct ShootQImportSummary {
    var contacts = 0
    var jobs = 0
    var invoices = 0
    var schedule = 0
    var receipts = 0
    var lines = 0
    var catalog = 0
    var skippedPartialLines = 0
    var lineSource = "none"
}

enum ShootQImportError: LocalizedError {
    case unreadable(String)
    case decode(String, String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            "Could not read \(name)."
        case .decode(let name, let detail):
            "Could not read \(name). \(detail)"
        }
    }
}

@MainActor
struct ShootQImporter {
    var context: ModelContext
    var onProgress: (String, Double) -> Void

    func run(folder: URL) async throws -> ShootQImportSummary {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer {
            if accessing { folder.stopAccessingSecurityScopedResource() }
        }

        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }

        var summary = ShootQImportSummary()
        await report("Reading contacts", 0.04)
        let active = try loadJSON("contacts-active.json", as: [ShootQContact].self, from: folder)
        let archived = (try? loadJSON("contacts-archived.json", as: [ShootQContact].self, from: folder)) ?? []

        var contacts = try indexed(Contact.self)
        let contactRows = active.map { ($0, false) } + archived.map { ($0, true) }
        for (offset, row) in contactRows.enumerated() {
            upsertContact(row.0, archivedDefault: row.1, into: &contacts)
            if offset % 300 == 299 {
                try context.save()
                let fraction = 0.05 + 0.18 * Double(offset) / Double(max(contactRows.count, 1))
                await report("Saving contacts", fraction)
            }
        }
        try context.save()
        summary.contacts = contactRows.count

        await report("Reading jobs", 0.28)
        let jobRows = try loadJSON("jobs.json", as: [ShootQJob].self, from: folder)
        let links = (try? loadJSON("job-contacts.json", as: [ShootQJobContact].self, from: folder)) ?? []
        var peopleByJob: [String: [String]] = [:]
        for link in links {
            peopleByJob[String(link.job), default: []].append(String(link.contact))
        }

        var jobs = try indexed(Job.self)
        for (offset, row) in jobRows.enumerated() {
            let job = upsertJob(row, into: &jobs)
            job.contact = linkedContact(jobID: row.id, ownerID: row.externalOwner?.id, peopleByJob: peopleByJob, contacts: contacts)
            if offset % 300 == 299 {
                try context.save()
                await report("Saving jobs", 0.30 + 0.12 * Double(offset) / Double(max(jobRows.count, 1)))
            }
        }
        try context.save()
        summary.jobs = jobRows.count

        await report("Reading invoices", 0.46)
        let invoiceRows = try loadJSON("invoices.json", as: [ShootQInvoice].self, from: folder)
        var invoices = try indexed(Invoice.self)
        for (offset, row) in invoiceRows.enumerated() {
            upsertInvoice(row, contacts: contacts, jobs: jobs, into: &invoices)
            if offset % 200 == 199 {
                try context.save()
                await report("Saving invoices", 0.48 + 0.12 * Double(offset) / Double(max(invoiceRows.count, 1)))
            }
        }
        try context.save()
        summary.invoices = invoiceRows.count

        await report("Reading scheduled payments", 0.64)
        let scheduleRows = (try? loadJSON("scheduled-payments.json", as: [ShootQSchedule].self, from: folder)) ?? []
        var schedule = try indexed(PaymentScheduleEntry.self)
        for row in scheduleRows {
            upsertSchedule(row, invoices: invoices, into: &schedule)
        }
        try context.save()
        summary.schedule = scheduleRows.count

        await report("Reading payments", 0.74)
        let receiptRows = (try? loadJSON("applied-payments.json", as: [ShootQAppliedPayment].self, from: folder)) ?? []
        var receipts = try indexed(PaymentReceipt.self)
        for row in receiptRows {
            upsertReceipt(row, invoices: invoices, into: &receipts)
        }
        try context.save()
        summary.receipts = receiptRows.count

        await report("Reading line items", 0.86)
        let loaded = ShootQLineLoader.load(from: folder)
        summary.lineSource = loaded.source
        summary.skippedPartialLines = loaded.skipped
        var catalog = try catalogIndex()
        var lineCount = 0
        var grouped: [String: [ImportedLine]] = [:]
        for line in loaded.lines {
            grouped[line.invoiceID, default: []].append(line)
        }
        for (invoiceID, rows) in grouped {
            guard let invoice = invoices[invoiceID] else { continue }
            if !invoice.lines.isEmpty { continue }
            for (position, row) in rows.enumerated() {
                let item = catalogItem(named: row.name, price: row.unitPrice, detail: row.detail, catalog: &catalog)
                let line = InvoiceLine(
                    name: row.name,
                    detail: row.detail,
                    quantity: row.quantity,
                    unitPrice: row.unitPrice,
                    position: position,
                    packageName: row.packageName
                )
                line.invoice = invoice
                line.catalogItem = item
                context.insert(line)
                lineCount += 1
            }
        }
        try context.save()
        summary.lines = lineCount
        summary.catalog = catalog.count
        await report("Books are in", 1)
        DebugPrint(mode: .import, "Imported \(summary.contacts) contacts, \(summary.invoices) invoices, \(summary.lines) lines from \(summary.lineSource)")
        return summary
    }

    // MARK: - Contacts

    private func upsertContact(_ row: ShootQContact, archivedDefault: Bool, into map: inout [String: Contact]) {
        let key = String(row.id)
        let contact = map[key] ?? Contact(shootqID: key)
        if map[key] == nil {
            context.insert(contact)
            map[key] = contact
        }
        contact.firstName = row.firstName ?? ""
        contact.lastName = row.lastName ?? ""
        let combined = "\(contact.firstName) \(contact.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        let full = (row.fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        contact.fullName = full.isEmpty ? combined : full
        contact.companyName = row.companyName ?? ""
        contact.email = row.defaultEmailDetails?.address ?? row.emails?.first?.address ?? ""
        contact.phone = row.defaultPhoneDetails?.number ?? row.phones?.first?.number ?? ""
        contact.address = addressLine(row.defaultAddressDetails ?? row.addresses?.first)
        contact.anniversary = anniversary(from: row.dates)
        contact.archived = row.archived ?? archivedDefault
        contact.createdAt = ShootQDates.parse(row.created) ?? contact.createdAt
    }

    private func addressLine(_ address: ShootQAddress?) -> String {
        guard let address else { return "" }
        if let full = address.fullAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !full.isEmpty {
            return full
        }
        return [address.street, address.city, address.state, address.zip]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func anniversary(from dates: [ShootQDateStamp]?) -> Date? {
        guard let stamp = dates?.first(where: { $0.dateType == "anniversary" }) else { return nil }
        if let parsed = ShootQDates.parse(stamp.displayDate) { return parsed }
        guard let year = stamp.year, let monthDay = stamp.date, monthDay.count == 4,
              let month = Int(monthDay.prefix(2)), let day = Int(monthDay.suffix(2)) else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    // MARK: - Jobs

    private func upsertJob(_ row: ShootQJob, into map: inout [String: Job]) -> Job {
        let key = String(row.id)
        let job = map[key] ?? Job(shootqID: key)
        if map[key] == nil {
            context.insert(job)
            map[key] = job
        }
        let name = (row.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        job.name = name.isEmpty ? "Untitled job" : name
        job.eventDate = ShootQDates.parse(row.mainEventDate)
        job.jobType = row.jobTypeDetails?.displayName ?? row.jobTypeDetails?.name ?? ""
        job.status = row.status ?? ""
        job.archived = job.status.localizedStandardContains("archived")
        return job
    }

    private func linkedContact(
        jobID: Int,
        ownerID: Int?,
        peopleByJob: [String: [String]],
        contacts: [String: Contact]
    ) -> Contact? {
        let options = peopleByJob[String(jobID)] ?? []
        if let ownerID {
            let ownerKey = String(ownerID)
            if options.contains(ownerKey) || options.isEmpty, let contact = contacts[ownerKey] {
                return contact
            }
        }
        for key in options {
            if let contact = contacts[key] { return contact }
        }
        return nil
    }

    // MARK: - Invoices

    private func upsertInvoice(
        _ row: ShootQInvoice,
        contacts: [String: Contact],
        jobs: [String: Job],
        into map: inout [String: Invoice]
    ) {
        let key = String(row.id)
        let invoice = map[key] ?? Invoice(shootqID: key)
        if map[key] == nil {
            context.insert(invoice)
            map[key] = invoice
        }
        let localPaid = invoice.amountPaid
        let importedNumber = row.number?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !importedNumber.isEmpty {
            invoice.number = importedNumber
        } else if invoice.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invoice.number = key
        }
        invoice.invoiceDate = ShootQDates.parse(row.invoiceDate) ?? invoice.invoiceDate
        invoice.dueDate = ShootQDates.parse(row.dueDate)
        invoice.paidDate = ShootQDates.parse(row.paidDate)
        invoice.tax = row.tax?.value ?? 0
        invoice.discount = row.discount?.value ?? 0
        invoice.shipping = row.shipping?.value ?? 0
        invoice.total = row.total?.value ?? 0
        invoice.amountPaid = row.paid?.value ?? 0
        invoice.balance = row.balance?.value ?? (invoice.total - invoice.amountPaid)
        if localPaid > invoice.amountPaid {
            invoice.amountPaid = localPaid
            invoice.balance = invoice.total - localPaid
        }
        invoice.collectManually = row.collectManually ?? true
        invoice.remindersDisabled = row.disableReminders ?? false
        invoice.note = row.message ?? ""
        invoice.isImported = true
        invoice.status = mappedStatus(row.status)
        if let contactID = row.contact {
            invoice.contact = contacts[String(contactID)]
        }
        if let jobID = row.job {
            invoice.job = jobs[String(jobID)]
        }
        let bill = (row.billTo?.fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        invoice.billToName = bill.isEmpty ? (invoice.contact?.displayName ?? "") : bill
        InvoiceMath.applyDerivedStatus(invoice)
    }

    private func mappedStatus(_ raw: String?) -> InvoiceStatus {
        switch raw?.lowercased() {
        case "paid": .paid
        case "void": .void
        case "draft": .draft
        case "overdue": .overdue
        case "pending": .pending
        default: .pending
        }
    }

    // MARK: - Payments

    private func upsertSchedule(
        _ row: ShootQSchedule,
        invoices: [String: Invoice],
        into map: inout [String: PaymentScheduleEntry]
    ) {
        let key = String(row.id)
        let entry = map[key] ?? PaymentScheduleEntry(shootqID: key)
        if map[key] == nil {
            context.insert(entry)
            map[key] = entry
        }
        entry.due = ShootQDates.parse(row.due)
        entry.amount = row.amount?.value ?? 0
        entry.amountPaid = row.paid?.value ?? 0
        entry.balance = row.balance?.value ?? 0
        entry.status = row.status ?? ""
        if let invoiceID = row.invoice {
            entry.invoice = invoices[String(invoiceID)]
        }
    }

    private func upsertReceipt(
        _ row: ShootQAppliedPayment,
        invoices: [String: Invoice],
        into map: inout [String: PaymentReceipt]
    ) {
        let key = String(row.id)
        let receipt = map[key] ?? PaymentReceipt(shootqID: key)
        if map[key] == nil {
            context.insert(receipt)
            map[key] = receipt
        }
        receipt.amount = row.amount?.value ?? 0
        receipt.paidAt = ShootQDates.parse(row.externalPayment?.datetime) ?? ShootQDates.parse(row.created) ?? receipt.paidAt
        receipt.method = mappedMethod(row.externalPayment?.paymentType)
        if let invoiceID = row.invoice {
            receipt.invoice = invoices[String(invoiceID)]
        }
    }

    private func mappedMethod(_ raw: String?) -> PaymentMethod {
        switch raw?.lowercased() {
        case "check": .check
        case "credit_card", "card": .card
        case "manual": .manual
        default: .other
        }
    }

    // MARK: - Catalog

    private func catalogIndex() throws -> [String: CatalogItem] {
        let items = try context.fetch(FetchDescriptor<CatalogItem>())
        var map: [String: CatalogItem] = [:]
        for item in items {
            map[item.name] = item
        }
        return map
    }

    private func catalogItem(
        named name: String,
        price: Decimal,
        detail: String,
        catalog: inout [String: CatalogItem]
    ) -> CatalogItem {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = catalog[key] {
            existing.defaultPrice = price
            if existing.detail.isEmpty, !detail.isEmpty {
                existing.detail = detail
            }
            existing.timesUsed += 1
            return existing
        }
        let created = CatalogItem(name: key, defaultPrice: price, detail: detail, timesUsed: 1)
        context.insert(created)
        catalog[key] = created
        return created
    }

    // MARK: - Store helpers

    private func indexed<Model: PersistentModel>(_ type: Model.Type) throws -> [String: Model] {
        let rows = try context.fetch(FetchDescriptor<Model>())
        var map: [String: Model] = [:]
        for row in rows {
            if let key = shootqKey(of: row) {
                map[key] = row
            }
        }
        return map
    }

    private func shootqKey<Model: PersistentModel>(of model: Model) -> String? {
        switch model {
        case let contact as Contact: contact.shootqID
        case let job as Job: job.shootqID
        case let invoice as Invoice: invoice.shootqID
        case let entry as PaymentScheduleEntry: entry.shootqID
        case let receipt as PaymentReceipt: receipt.shootqID
        default: nil
        }
    }

    private func loadJSON<T: Decodable>(_ name: String, as type: T.Type, from folder: URL) throws -> T {
        let url = folder.appendingPathComponent(name)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ShootQImportError.unreadable(name)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ShootQImportError.decode(name, error.localizedDescription)
        }
    }

    private func report(_ title: String, _ fraction: Double) async {
        onProgress(title, fraction)
        await Task.yield()
    }
}
