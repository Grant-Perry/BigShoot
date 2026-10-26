import Foundation
import SwiftData
import Testing
@testable import BigQ

@MainActor
struct BackupTests {
    @Test func fullBackupRestoresTheStudio() throws {
        let defaults = isolatedDefaults()
        defaults.set("North Light", forKey: StudioBanner.key)
        defaults.set(["Portrait"], forKey: JobTypeCatalog.storageKey)
        defaults.set(["Zelle"], forKey: PaymentMethodCatalog.storageKey)

        let source = try makeContainer()
        let context = source.mainContext
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let studio = StudioBrand(name: "North Light", email: "hello@north.test", isPrimary: true, createdAt: when)
        studio.logoImageData = Data("logo".utf8)
        studio.logoImageSourceData = Data("source".utf8)
        let contact = Contact(
            shootqID: "c1",
            firstName: "Ada",
            lastName: "Lovelace",
            fullName: "Ada Lovelace",
            email: "ada@north.test",
            createdAt: when
        )
        let job = Job(shootqID: "j1", name: "Wedding", eventDate: when, jobType: "Weddings", contact: contact)
        let catalog = CatalogItem(name: "Album", defaultPrice: Decimal(string: "1200")!, detail: "Leather", taxable: true, timesUsed: 3)
        let tax = TaxSchedule(name: "State", rate: Decimal(string: "0.066")!)
        let invoice = Invoice(
            shootqID: "i1",
            number: "1042",
            invoiceDate: when,
            dueDate: when.addingTimeInterval(86_400),
            status: .pending,
            tax: Decimal(string: "79.20")!,
            taxRate: Decimal(string: "0.066")!,
            taxScheduleName: "State",
            invoiceTaxable: true,
            total: Decimal(string: "1279.20")!,
            amountPaid: Decimal(string: "200")!,
            balance: Decimal(string: "1079.20")!,
            billToName: "Ada Lovelace",
            note: "Balcony",
            closing: "With thanks",
            submittedAt: when,
            isImported: true
        )
        invoice.contact = contact
        invoice.job = job
        invoice.studio = studio
        let line = InvoiceLine(shootqID: "l1", name: "Album", quantity: 1, unitPrice: Decimal(string: "1200")!, position: 0, taxable: true)
        line.catalogItem = catalog
        line.invoice = invoice
        let receipt = PaymentReceipt(shootqID: "p1", paidAt: when, amount: Decimal(string: "200")!, method: .check)
        receipt.invoice = invoice
        let scheduled = PaymentScheduleEntry(shootqID: "s1", due: when, amount: 200, amountPaid: 200, balance: 0, status: "paid")
        scheduled.invoice = invoice
        let contract = Contract(
            shootqID: "k1",
            title: "Wedding Agreement",
            status: "signed",
            html: "<p>Signed terms</p>",
            eventLabel: "Oct 26",
            sentAt: when,
            job: job
        )
        let signature = ContractSignature(
            displayName: "Ada Lovelace",
            completed: true,
            signedAt: when,
            ipAddress: "127.0.0.1",
            shootqContactID: "c1",
            contact: contact
        )
        signature.contract = contract
        let event = BooksEvent(
            occurredAt: when,
            kind: .paymentApplied,
            invoiceKey: "i1",
            invoiceNumber: "1042",
            clientName: "Ada Lovelace",
            amount: 200,
            detail: "Check"
        )
        context.insert(studio)
        context.insert(contact)
        context.insert(job)
        context.insert(catalog)
        context.insert(tax)
        context.insert(invoice)
        context.insert(line)
        context.insert(receipt)
        context.insert(scheduled)
        context.insert(contract)
        context.insert(signature)
        context.insert(event)
        try context.save()

        let folder = temporaryPackage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let written = try BackupExport.write(context: context, scope: .full, defaults: defaults, to: folder, createdAt: when)
        #expect(written.bodiesWritten == 1)
        #expect(written.counts.contracts == 1)
        #expect(!contact.archiveID.isEmpty)

        defaults.set("Changed", forKey: StudioBanner.key)
        let restoredDefaults = isolatedDefaults()
        let destination = try makeContainer()
        let payload = try BackupPackage.load(at: folder)
        _ = try BackupRestore.apply(payload, mode: .replace, context: destination.mainContext, defaults: restoredDefaults)

        let studios = try destination.mainContext.fetch(FetchDescriptor<StudioBrand>())
        #expect(studios.count == 1)
        #expect(studios[0].name == "North Light")
        #expect(studios[0].isPrimary)
        #expect(studios[0].logoImageData == Data("logo".utf8))
        #expect(studios[0].logoImageSourceData == Data("source".utf8))

        let contacts = try destination.mainContext.fetch(FetchDescriptor<Contact>())
        #expect(contacts.map(\.fullName) == ["Ada Lovelace"])
        let jobs = try destination.mainContext.fetch(FetchDescriptor<Job>())
        #expect(jobs.first?.contact?.fullName == "Ada Lovelace")
        let invoices = try destination.mainContext.fetch(FetchDescriptor<Invoice>())
        let restoredInvoice = try #require(invoices.first)
        #expect(restoredInvoice.number == "1042")
        #expect(restoredInvoice.total == Decimal(string: "1279.20"))
        #expect(restoredInvoice.taxRate == Decimal(string: "0.066"))
        #expect(restoredInvoice.note == "Balcony")
        #expect(restoredInvoice.closing == "With thanks")
        #expect(restoredInvoice.contact?.email == "ada@north.test")
        #expect(restoredInvoice.job?.name == "Wedding")
        #expect(restoredInvoice.studio?.name == "North Light")
        #expect(restoredInvoice.lines.first?.unitPrice == Decimal(string: "1200"))
        #expect(restoredInvoice.lines.first?.catalogItem?.name == "Album")
        #expect(restoredInvoice.receipts.first?.methodRaw == "check")
        #expect(restoredInvoice.schedule.first?.status == "paid")

        let contracts = try destination.mainContext.fetch(FetchDescriptor<Contract>())
        let restoredContract = try #require(contracts.first)
        #expect(restoredContract.html == "<p>Signed terms</p>")
        #expect(restoredContract.job?.name == "Wedding")
        #expect(restoredContract.signatures.first?.contact?.fullName == "Ada Lovelace")
        #expect(restoredContract.signatures.first?.completed == true)

        let events = try destination.mainContext.fetch(FetchDescriptor<BooksEvent>())
        #expect(events.first?.detail == "Check")
        let catalogItems = try destination.mainContext.fetch(FetchDescriptor<CatalogItem>())
        #expect(catalogItems.first?.timesUsed == 3)
        #expect(catalogItems.first?.taxable == true)
        let taxes = try destination.mainContext.fetch(FetchDescriptor<TaxSchedule>())
        #expect(taxes.first?.rate == Decimal(string: "0.066"))
        #expect(restoredDefaults.string(forKey: StudioBanner.key) == "North Light")
        #expect(restoredDefaults.stringArray(forKey: JobTypeCatalog.storageKey) == ["Portrait"])
        #expect(restoredDefaults.stringArray(forKey: PaymentMethodCatalog.storageKey) == ["Zelle"])
    }

    @Test func updatingABackupLeavesAgreementFiles() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let contract = Contract(shootqID: "k1", title: "Wedding Agreement", status: "signed", html: "<p>Signed terms</p>")
        context.insert(contract)
        try context.save()

        let folder = temporaryPackage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try BackupExport.write(context: context, scope: .books, defaults: isolatedDefaults(), to: folder)
        #expect(first.bodiesWritten == 1)
        #expect(first.counts.catalog == 0)
        let archiveID = contract.archiveID
        let body = folder
            .appendingPathComponent("bodies")
            .appendingPathComponent("\(BackupIdentity.digest("<p>Signed terms</p>")).html")
        try Data("tampered".utf8).write(to: body)

        let second = try BackupExport.write(context: context, scope: .books, defaults: isolatedDefaults(), to: folder)
        #expect(second.bodiesWritten == 0)
        #expect(second.bodiesSkipped == 1)
        #expect(contract.archiveID == archiveID)
        #expect(try Data(contentsOf: body) == Data("tampered".utf8))

        contract.html = "<p>Changed</p>"
        let third = try BackupExport.write(context: context, scope: .books, defaults: isolatedDefaults(), to: folder)
        #expect(third.bodiesWritten == 1)
        let changed = folder
            .appendingPathComponent("bodies")
            .appendingPathComponent("\(BackupIdentity.digest("<p>Changed</p>")).html")
        #expect(FileManager.default.fileExists(atPath: changed.path))
        #expect(try Data(contentsOf: body) == Data("tampered".utf8))
    }

    @Test func mergeKeepsLocalRecordsAndUpdatesMatches() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let contact = Contact(shootqID: "c1", fullName: "Ada Lovelace", email: "ada@north.test")
        let invoice = Invoice(shootqID: "i1", number: "1042", total: 10, balance: 10, billToName: "Ada Lovelace")
        invoice.contact = contact
        context.insert(contact)
        context.insert(invoice)
        try context.save()

        let folder = temporaryPackage()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try BackupExport.write(context: context, scope: .full, defaults: isolatedDefaults(), to: folder)

        invoice.total = 99
        invoice.balance = 99
        let local = Contact(fullName: "Local Only", email: "local@north.test")
        let localInvoice = Invoice(number: "LOCAL", total: 5, balance: 5, billToName: "Local Only")
        context.insert(local)
        context.insert(localInvoice)
        context.delete(contact)
        try context.save()

        let payload = try BackupPackage.load(at: folder)
        _ = try BackupRestore.apply(payload, mode: .merge, context: context, defaults: isolatedDefaults())

        let contacts = try context.fetch(FetchDescriptor<Contact>())
        #expect(Set(contacts.map(\.fullName)) == ["Ada Lovelace", "Local Only"])
        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        let restored = try #require(invoices.first { $0.number == "1042" })
        #expect(restored.total == 10)
        #expect(restored.contact?.fullName == "Ada Lovelace")
        #expect(invoices.contains { $0.number == "LOCAL" })
    }

    @Test func catalogReplaceLeavesTheBooks() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let catalog = CatalogItem(name: "Album", defaultPrice: 100, detail: "Leather")
        let invoice = Invoice(number: "1042", total: 100, balance: 100)
        let line = InvoiceLine(name: "Album", quantity: 1, unitPrice: 100)
        line.catalogItem = catalog
        line.invoice = invoice
        context.insert(catalog)
        context.insert(invoice)
        context.insert(line)
        try context.save()

        let folder = temporaryPackage()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try BackupExport.write(context: context, scope: .catalog, defaults: isolatedDefaults(), to: folder)
        catalog.defaultPrice = 5
        invoice.note = "Keep this invoice"
        try context.save()

        let payload = try BackupPackage.load(at: folder)
        #expect(payload.file.contracts.isEmpty)
        #expect(payload.file.invoices.isEmpty)
        _ = try BackupRestore.apply(payload, mode: .replace, context: context, defaults: isolatedDefaults())

        let items = try context.fetch(FetchDescriptor<CatalogItem>())
        #expect(items.count == 1)
        #expect(items[0].defaultPrice == 100)
        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        #expect(invoices.first?.note == "Keep this invoice")
        #expect(invoices.first?.lines.first?.catalogItem?.name == "Album")
    }

    @Test func booksReplaceLeavesThePriceList() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let catalog = CatalogItem(name: "Album", defaultPrice: 100)
        let contract = Contract(shootqID: "k1", title: "Wedding Agreement", status: "signed", html: "<p>Signed terms</p>")
        context.insert(catalog)
        context.insert(contract)
        try context.save()

        let folder = temporaryPackage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let written = try BackupExport.write(context: context, scope: .books, defaults: isolatedDefaults(), to: folder)
        #expect(written.counts.catalog == 0)
        #expect(written.counts.contracts == 1)
        let poster = CatalogItem(name: "Poster", defaultPrice: 40)
        context.insert(poster)
        contract.html = "gone"
        try context.save()

        let payload = try BackupPackage.load(at: folder)
        _ = try BackupRestore.apply(payload, mode: .replace, context: context, defaults: isolatedDefaults())
        let names = Set(try context.fetch(FetchDescriptor<CatalogItem>()).map(\.name))
        #expect(names == ["Album", "Poster"])
        let contracts = try context.fetch(FetchDescriptor<Contract>())
        #expect(contracts.first?.html == "<p>Signed terms</p>")
    }

    @Test func mergePreferencesKeepLocalLists() throws {
        let defaults = isolatedDefaults()
        defaults.set("North Light", forKey: StudioBanner.key)
        defaults.set(["Portrait"], forKey: JobTypeCatalog.storageKey)
        defaults.set(["Zelle"], forKey: PaymentMethodCatalog.storageKey)
        let container = try makeContainer()
        let context = container.mainContext
        let folder = temporaryPackage()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try BackupExport.write(context: context, scope: .full, defaults: defaults, to: folder)

        defaults.set("Changed", forKey: StudioBanner.key)
        defaults.set(["Portrait", "Headshots"], forKey: JobTypeCatalog.storageKey)
        defaults.set(["Zelle", "Wire"], forKey: PaymentMethodCatalog.storageKey)
        let payload = try BackupPackage.load(at: folder)
        _ = try BackupRestore.apply(payload, mode: .merge, context: context, defaults: defaults)
        #expect(defaults.string(forKey: StudioBanner.key) == "North Light")
        #expect(defaults.stringArray(forKey: JobTypeCatalog.storageKey) == ["Portrait", "Headshots"])
        #expect(defaults.stringArray(forKey: PaymentMethodCatalog.storageKey) == ["Zelle", "Wire"])
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StudioSchemaV9.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func temporaryPackage() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bigq-backup-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Studio.bigqbackup", isDirectory: true)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "BigQ.Backup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
