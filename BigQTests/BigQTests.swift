import Foundation
import PDFKit
import SwiftData
import Testing
@testable import BigQ

@MainActor
struct BigQTests {
    @Test func jobTypeCatalogStartsWithCommercialAndWeddings() {
        let catalog = JobTypeCatalog(defaults: isolatedDefaults("empty"))
        #expect(catalog.names == ["Commercial", "Weddings"])
    }

    @Test func bannerTextFallsBackWhenBlank() {
        #expect(StudioBanner.resolved("BigQ") == "BigQ")
        #expect(StudioBanner.resolved("  Studio books  ") == "Studio books")
        #expect(StudioBanner.resolved("   ") == StudioBanner.fallback)
        #expect(StudioBanner.resolved("") == "BigQ")
    }

    @Test func paymentMethodCatalogStartsWithBuiltInsSorted() {
        let catalog = PaymentMethodCatalog(defaults: isolatedDefaults("pay-empty"))
        #expect(catalog.titles == ["Card", "Check", "Manual"])
    }

    @Test func paymentMethodCatalogSortsNewTypesAndRejectsDuplicates() {
        let defaults = isolatedDefaults("pay-added")
        let catalog = PaymentMethodCatalog(defaults: defaults)
        #expect(catalog.add("  Bank Transfer  ") == .added("Bank Transfer"))
        #expect(catalog.add("Zelle") == .added("Zelle"))
        #expect(catalog.add("bank transfer") == .duplicate("Bank Transfer"))
        #expect(catalog.add("CHECK") == .duplicate("Check"))
        #expect(catalog.add("manual") == .duplicate("Manual"))
        #expect(catalog.add("Other") == .duplicate("Other"))
        #expect(catalog.add("   ") == .empty)
        #expect(catalog.titles == ["Bank Transfer", "Card", "Check", "Manual", "Zelle"])
        let reloaded = PaymentMethodCatalog(defaults: defaults)
        #expect(reloaded.titles == ["Bank Transfer", "Card", "Check", "Manual", "Zelle"])
    }

    @Test func customPaymentMethodKeepsItsName() {
        let receipt = PaymentReceipt(amount: 12, method: .check)
        #expect(receipt.methodTitle == "Check")
        receipt.methodRaw = "Bank Transfer"
        #expect(receipt.methodTitle == "Bank Transfer")
    }

    @Test func jobTypeCatalogRemembersAddedTypes() {
        let defaults = isolatedDefaults("added")
        let catalog = JobTypeCatalog(defaults: defaults)
        #expect(catalog.add("  Portrait  ") == "Portrait")
        #expect(catalog.add("weddings") == "Weddings")
        #expect(catalog.add("   ") == nil)
        let reloaded = JobTypeCatalog(defaults: defaults)
        #expect(reloaded.names == ["Commercial", "Weddings", "Portrait"])
    }

    @Test func overdueWhenBalanceRemainsPastDue() {
        let due = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 86_400 * 30)
        let status = InvoiceMath.displayStatus(stored: .pending, balance: 1400, dueDate: due, now: now)
        #expect(status == .overdue)
    }

    @Test func paidWhenBalanceIsZero() {
        let status = InvoiceMath.displayStatus(stored: .pending, balance: 0, dueDate: .now)
        #expect(status == .paid)
    }

    @Test func voidStaysVoid() {
        let status = InvoiceMath.displayStatus(stored: .void, balance: 50, dueDate: .distantPast)
        #expect(status == .void)
    }

    @Test func draftStaysDraft() {
        let status = InvoiceMath.displayStatus(stored: .draft, balance: 0, dueDate: nil)
        #expect(status == .draft)
    }

    @Test func invoiceListDefaultsToOpenAndSplitsOverdue() throws {
        let past = Date(timeIntervalSince1970: 0)
        let future = Date.now.addingTimeInterval(86_400 * 30)
        let schema = Schema(versionedSchema: StudioSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let pending = Invoice(number: "1", dueDate: future, status: .pending, balance: 100)
        let overdue = Invoice(number: "2", dueDate: past, status: .pending, balance: 40)
        let draft = Invoice(number: "3", dueDate: past, status: .draft, balance: 10)
        let paid = Invoice(number: "4", dueDate: past, status: .paid, balance: 0)
        let voided = Invoice(number: "5", dueDate: past, status: .void, balance: 25)
        for invoice in [pending, overdue, draft, paid, voided] {
            context.insert(invoice)
        }

        #expect(InvoiceScope.open.includes(pending))
        #expect(InvoiceScope.open.includes(overdue))
        #expect(InvoiceScope.open.includes(draft))
        #expect(!InvoiceScope.open.includes(paid))
        #expect(!InvoiceScope.open.includes(voided))

        #expect(overdue.displayStatus == .overdue)
        #expect(InvoiceScope.overdue.includes(overdue))
        #expect(!InvoiceScope.overdue.includes(pending))
        #expect(!InvoiceScope.overdue.includes(draft))
        #expect(!InvoiceScope.overdue.includes(paid))
        #expect(!InvoiceScope.overdue.includes(voided))

        #expect(InvoiceScope.allCases.map(\.title) == ["Open", "Overdue", "All"])
        #expect(InvoiceScope.all.includes(paid))
        #expect(InvoiceScope.all.includes(voided))
    }

    @Test func openBalanceIsOnlyUnsettledInvoices() {
        let past = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 86_400 * 30)
        #expect(InvoiceMath.holdsOpenBalance(stored: .pending, balance: 100, dueDate: .now))
        #expect(InvoiceMath.holdsOpenBalance(stored: .draft, balance: 0, dueDate: nil))
        #expect(InvoiceMath.holdsOpenBalance(stored: .pending, balance: 10, dueDate: past, now: now))
        #expect(!InvoiceMath.holdsOpenBalance(stored: .pending, balance: 0, dueDate: .now))
        #expect(!InvoiceMath.holdsOpenBalance(stored: .void, balance: 50, dueDate: past))
    }

    @Test func nextNumberClearsTheHighestImported() {
        #expect(InvoiceMath.nextNumber(among: ["84409", "", "12"]) == "84410")
    }

    @Test func countdownCountsDaysLeftAndPast() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let ahead = calendar.date(byAdding: .day, value: 28, to: today)!
        let behind = calendar.date(byAdding: .day, value: -98, to: today)!
        #expect(InvoiceMath.dueCountdown(until: ahead, now: today) == "28 days left")
        #expect(InvoiceMath.dueCountdown(until: today, now: today) == "Due today")
        #expect(InvoiceMath.dueCountdown(until: behind, now: today) == "98 days past due")
    }

    @Test func daysToPayCountsFromTheInvoiceDate() {
        let calendar = Calendar.current
        let invoiced = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let sameDay = invoiced
        let nextDay = calendar.date(byAdding: .day, value: 1, to: invoiced)!
        let later = calendar.date(byAdding: .day, value: 29, to: invoiced)!
        let before = calendar.date(byAdding: .day, value: -2, to: invoiced)!
        #expect(InvoiceMath.daysToPay(from: invoiced, paidAt: sameDay) == "Paid same day")
        #expect(InvoiceMath.daysToPay(from: invoiced, paidAt: nextDay) == "Paid in 1 day")
        #expect(InvoiceMath.daysToPay(from: invoiced, paidAt: later) == "Paid in 29 days")
        #expect(InvoiceMath.daysToPay(from: invoiced, paidAt: before) == "2 days before the invoice")
    }

    @Test func blankShootQNumberShowsTheInvoiceID() throws {
        let schema = Schema(versionedSchema: StudioSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let blank = Invoice(shootqID: "1234867", number: "", status: .pending)
        let numbered = Invoice(shootqID: "711118", number: "1849771", status: .paid)
        let draft = Invoice(status: .draft)
        context.insert(blank)
        context.insert(numbered)
        context.insert(draft)

        #expect(blank.displayNumber == "1234867")
        #expect(numbered.displayNumber == "1849771")
        #expect(draft.displayNumber == "Draft")
        #expect(blank.dueSummary == nil)
    }

    @Test func lineTotalMultiplies() {
        #expect(InvoiceMath.lineTotal(quantity: 2, unitPrice: Decimal(string: "395.00")!) == Decimal(string: "790.00"))
    }

    @Test func csvKeepsCommasInsideQuotes() {
        let rows = ShootQCSV.parse("name,detail\n\"Day Rate\",\"hello, world\"\n")
        #expect(rows.count == 1)
        #expect(rows[0]["name"] == "Day Rate")
        #expect(rows[0]["detail"] == "hello, world")
    }

    @Test func importsLocalShootQExport() async throws {
        let folder = ShootQImportModel.realHome
            .appendingPathComponent("Xcode/BigQ/shootq-export", isDirectory: true)
        let marker = folder.appendingPathComponent("contacts-active.json")
        try #require(FileManager.default.isReadableFile(atPath: marker.path))

        let schema = Schema(versionedSchema: StudioSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let summary = try await ShootQImporter(context: container.mainContext) { _, _ in }.run(folder: folder)

        #expect(summary.contacts == 2443)
        #expect(summary.jobs == 2134)
        #expect(summary.invoices == 744)
        #expect(summary.schedule == 1096)
        #expect(summary.receipts == 1117)
        #expect(summary.lines > 0)
    }

    @Test func deleteGuardNamesTheBalanceAndTheTrail() {
        let invoice = Invoice(
            number: "1849451",
            status: .pending,
            total: Decimal(string: "4386.61")!,
            balance: Decimal(string: "4386.61")!,
            billToName: "Snow Companies",
            isImported: true
        )
        #expect(InvoiceRemoval.title(for: invoice) == "Delete 1849451?")
        let message = InvoiceRemoval.message(for: invoice)
        #expect(message.contains("Snow Companies"))
        #expect(message.contains("No payments"))
        #expect(message.contains("audit trail"))
    }

    @Test func v1StoreMigratesWithoutLosingInvoices() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("bigshoot-migrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appendingPathComponent("BigQ.store")
        try writeVersion1Invoice(at: storeURL)

        let schema = Schema(versionedSchema: StudioSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: StudioMigrationPlan.self,
            configurations: [configuration]
        )
        let invoices = try container.mainContext.fetch(FetchDescriptor<Invoice>())
        #expect(invoices.count == 1)
        #expect(invoices.first?.number == "1849451")
        #expect(invoices.first?.clientName == "Snow Companies")
        let event = BooksEvent(
            kind: .deleted,
            invoiceKey: "kept",
            invoiceNumber: "1849451",
            clientName: "Snow Companies",
            amount: 1,
            detail: "migration check"
        )
        container.mainContext.insert(event)
        try container.mainContext.save()
        let events = try container.mainContext.fetch(FetchDescriptor<BooksEvent>())
        #expect(events.count == 1)
    }

    @Test func deletingAnInvoiceKeepsTheAuditTrail() throws {
        let container = try makeBooksContainer()
        let context = container.mainContext
        let invoice = Invoice(
            shootqID: "1849451",
            number: "1849451",
            status: .pending,
            total: Decimal(string: "4386.61")!,
            balance: Decimal(string: "4386.61")!,
            billToName: "Snow Companies",
            isImported: true
        )
        context.insert(invoice)
        BooksTrail.notePayment(invoice, amount: Decimal(string: "100.00")!, method: .check, in: context)
        invoice.amountPaid = Decimal(string: "100.00")!
        invoice.balance = Decimal(string: "4286.61")!
        try InvoiceRemoval.remove(invoice, in: context)

        let events = try context.fetch(FetchDescriptor<BooksEvent>())
        #expect(events.count == 2)
        let deleted = try #require(events.first { $0.kind == .deleted })
        #expect(deleted.invoiceNumber == "1849451")
        #expect(deleted.clientName == "Snow Companies")
        #expect(deleted.invoiceKey == "1849451")
        #expect(deleted.detail.contains(StudioMoney.string(Decimal(string: "4286.61")!)))
        let payment = try #require(events.first { $0.kind == .paymentApplied })
        #expect(payment.amount == Decimal(string: "100.00"))
        #expect(payment.detail.contains("Check"))
        let remaining = try context.fetch(FetchDescriptor<Invoice>())
        #expect(remaining.isEmpty)
    }

    @Test func netDaysCountsFromTheShootAndDefaultsTo45() {
        let calendar = Calendar.current
        let shoot = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        let draft = InvoiceDraftModel()
        #expect(draft.netDays == 45)

        draft.invoiceDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        draft.job = Job(name: "Jeremy", eventDate: shoot)
        draft.netDays = 45
        draft.applyNetDays()
        let fortyFiveAfterShoot = calendar.date(from: DateComponents(year: 2026, month: 12, day: 4))!
        #expect(calendar.isDate(draft.dueDate, inSameDayAs: fortyFiveAfterShoot))

        draft.dueDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))!
        draft.syncNetDaysFromDueDate()
        #expect(draft.netDays == 15)

        draft.job = nil
        draft.netDays = 7
        draft.applyNetDays()
        let sevenAfterInvoice = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29))!
        #expect(calendar.isDate(draft.dueDate, inSameDayAs: sevenAfterInvoice))
    }

    @Test func openInvoicesCanBeEditedIncludingImports() {
        let imported = Invoice(status: .pending, balance: 10, isImported: true)
        let local = Invoice(status: .draft, balance: 10, isImported: false)
        let paid = Invoice(status: .paid, balance: 0, isImported: true)
        let settled = Invoice(status: .pending, balance: 0, isImported: true)
        let voided = Invoice(status: .void, balance: 40, isImported: true)
        #expect(imported.canEditLines)
        #expect(local.canEditLines)
        #expect(!paid.canEditLines)
        #expect(!settled.canEditLines)
        #expect(!voided.canEditLines)
    }

    @Test func editingAnImportedInvoiceKeepsItsIdentityAndPayments() throws {
        let container = try makeBooksContainer()
        let context = container.mainContext
        let invoice = Invoice(
            shootqID: "1234867",
            number: "",
            status: .pending,
            discount: Decimal(string: "25.00")!,
            shipping: Decimal(string: "10.00")!,
            total: Decimal(string: "10157.30")!,
            amountPaid: Decimal(string: "100.00")!,
            balance: Decimal(string: "10057.30")!,
            billToName: "Snow Companies",
            isImported: true
        )
        context.insert(invoice)
        let line = InvoiceLine(
            name: "Photography Day Rate",
            quantity: 2,
            unitPrice: Decimal(string: "4750.00")!,
            position: 0
        )
        line.invoice = invoice
        context.insert(line)
        try context.save()

        let draft = InvoiceDraftModel()
        draft.load(invoice)
        #expect(draft.editingSentInvoice)
        draft.lines[0].unitPrice = Decimal(string: "4800.00")!
        _ = try draft.save(in: context, markSent: false)

        #expect(invoice.displayNumber == "1234867")
        #expect(invoice.isImported)
        #expect(invoice.status == .pending)
        #expect(invoice.amountPaid == Decimal(string: "100.00")!)
        #expect(invoice.discount == Decimal(string: "25.00")!)
        #expect(invoice.shipping == Decimal(string: "10.00")!)
        #expect(invoice.total == Decimal(string: "9585.00")!)
        #expect(invoice.balance == Decimal(string: "9485.00")!)
        let events = try context.fetch(FetchDescriptor<BooksEvent>())
        let edited = try #require(events.first { $0.kind == .edited })
        #expect(edited.invoiceKey == "1234867")
        #expect(edited.detail.contains("Total \(StudioMoney.string(Decimal(string: "10157.30")!)) → \(StudioMoney.string(Decimal(string: "9585.00")!))"))
        #expect(edited.detail.contains("Photography Day Rate"))
        #expect(edited.detail.contains(StudioMoney.string(Decimal(string: "4750.00")!)))
        #expect(edited.detail.contains(StudioMoney.string(Decimal(string: "4800.00")!)))
        #expect(!edited.detail.contains("Discount"))
    }

    @Test func editTrailSaysWhenNothingChanged() {
        let snapshot = BooksTrail.EditSnapshot(
            clientName: "Snow Companies",
            jobName: "Joseph",
            invoiceDate: Date(timeIntervalSince1970: 1_700_000_000),
            dueDate: nil,
            tax: 0,
            discount: 0,
            shipping: 0,
            note: "",
            total: 100,
            balance: 100,
            lines: [
                BooksTrail.EditSnapshot.Line(name: "Day Rate", quantity: 1, unitPrice: 100, detail: "")
            ]
        )
        let detail = BooksTrail.editDetail(number: "1234867", before: snapshot, after: snapshot)
        #expect(detail == "Edited 1234867. Nothing on the invoice changed.")
    }

    @Test func taxRateUnderstandsPercentAndFraction() {
        #expect(TaxRateInput.fraction(from: "6.6") == Decimal(string: "0.066"))
        #expect(TaxRateInput.fraction(from: "6.6%") == Decimal(string: "0.066"))
        #expect(TaxRateInput.fraction(from: "0.066") == Decimal(string: "0.066"))
        #expect(TaxRateInput.fraction(from: ".066") == Decimal(string: "0.066"))
        #expect(TaxRateInput.fraction(from: "1") == Decimal(string: "0.01"))
        #expect(TaxRateInput.fraction(from: "") == 0)
        #expect(TaxRateInput.percentText(for: Decimal(string: "0.066")!) == "6.6")
    }

    @Test func taxAmountUsesOnlyTaxableLinesAndJoinsTheBalance() throws {
        let container = try makeBooksContainer()
        let context = container.mainContext
        let invoice = Invoice(
            status: .pending,
            tax: 40,
            amountPaid: 100,
            billToName: "Snow Companies"
        )
        context.insert(invoice)
        let day = InvoiceLine(name: "Day Rate", quantity: 1, unitPrice: 1000, taxable: false)
        let print = InvoiceLine(name: "Print", quantity: 1, unitPrice: 50, position: 1, taxable: false)
        day.invoice = invoice
        print.invoice = invoice
        context.insert(day)
        context.insert(print)
        try context.save()

        let draft = InvoiceDraftModel()
        draft.load(invoice)
        #expect(draft.tax == 40)

        draft.lines[0].taxable = true
        #expect(draft.tax == 40)

        draft.taxRateText = "6.6"
        draft.commitTaxRate(schedules: [])
        #expect(draft.invoiceTaxable)
        #expect(draft.taxRate == Decimal(string: "0.066"))
        #expect(draft.tax == Decimal(string: "66.00"))
        #expect(draft.total == Decimal(string: "1116.00"))

        draft.invoiceTaxable = false
        #expect(draft.tax == 0)
        #expect(draft.total == Decimal(string: "1050.00"))
        draft.invoiceTaxable = true

        _ = try draft.save(in: context, markSent: false)
        #expect(invoice.tax == Decimal(string: "66.00"))
        #expect(invoice.taxRate == Decimal(string: "0.066"))
        #expect(invoice.total == Decimal(string: "1116.00"))
        #expect(invoice.balance == Decimal(string: "1016.00"))
        #expect(invoice.lines.first { $0.name == "Day Rate" }?.taxable == true)
        #expect(invoice.lines.first { $0.name == "Print" }?.taxable == false)
    }

    @Test func catalogEditsStayOffInvoicesAlreadyWritten() throws {
        let container = try makeBooksContainer()
        let context = container.mainContext
        let item = CatalogItem(name: "Day Rate", defaultPrice: 5000, taxable: false)
        context.insert(item)
        let invoice = Invoice(status: .pending, total: 5000, balance: 5000, billToName: "Snow Companies")
        context.insert(invoice)
        let line = InvoiceLine(name: "Day Rate", quantity: 1, unitPrice: 5000, taxable: false)
        line.invoice = invoice
        line.catalogItem = item
        context.insert(line)
        try context.save()

        item.defaultPrice = 7500
        item.taxable = true
        item.detail = "New wording"
        try context.save()

        #expect(line.unitPrice == 5000)
        #expect(line.taxable == false)
        #expect(line.name == "Day Rate")
        #expect(line.detail == "")

        let draft = InvoiceDraftModel()
        draft.addCatalogItem(item)
        #expect(draft.lines[0].unitPrice == 7500)
        #expect(draft.lines[0].taxable)
        item.defaultPrice = 9000
        item.taxable = false
        #expect(draft.lines[0].unitPrice == 7500)
        #expect(draft.lines[0].taxable)
    }

    @Test func seededStudioClaimsExistingInvoicesAndStaysPut() throws {
        let container = try makeBooksContainer()
        let context = container.mainContext
        let invoice = Invoice(number: "1849772", status: .pending, billToName: "Snow Companies")
        context.insert(invoice)
        try StudioBrandDirectory.prepare(in: context)

        let studios = try context.fetch(FetchDescriptor<StudioBrand>())
        let primary = try #require(studios.first)
        #expect(studios.count == 1)
        #expect(primary.name == StudioBrand.defaultName)
        #expect(primary.isPrimary)
        #expect(invoice.studio?.persistentModelID == primary.persistentModelID)

        let second = StudioBrand(name: "North Studio", email: "north@example.com", phone: "804-555-0100", address: "Richmond, VA")
        context.insert(second)
        try context.save()
        try StudioBrandDirectory.makePrimary(second, in: context)
        #expect(second.isPrimary)
        #expect(!primary.isPrimary)
        #expect(invoice.studio?.persistentModelID == primary.persistentModelID)

        try StudioBrandDirectory.delete(second, in: context)
        #expect(invoice.studio?.persistentModelID == primary.persistentModelID)
        #expect(primary.isPrimary)
        let remaining = try context.fetch(FetchDescriptor<StudioBrand>())
        #expect(remaining.count == 1)
    }

    @Test func invoicePDFPrintsTheIssuingStudio() throws {
        let studio = StudioBrand(
            name: "Grant & Deb Photographers",
            email: "grant@grantdeb.com",
            phone: "804-555-0199",
            address: "Richmond, VA",
            isPrimary: true
        )
        let invoice = Invoice(number: "1849772", status: .pending, billToName: "Snow Companies")
        invoice.studio = studio
        invoice.contact = Contact(email: "client@snow.example")
        invoice.job = Job(name: "2026-10-20-BOE-Jeremy-SHV")
        let data = InvoicePDFRenderer.render(invoice)
        let text = try #require(PDFDocument(data: data)?.string)
        #expect(text.contains("Grant & Deb Photographers"))
        #expect(text.contains("grant@grantdeb.com"))
        #expect(text.contains("804-555-0199"))
        #expect(text.contains("Richmond, VA"))
        #expect(text.contains("Invoice"))
        #expect(text.contains("1849772"))
        #expect(!text.contains("Pending"))
        #expect(text.contains("client@snow.example"))
        #expect(text.contains("Job: 2026-10-20-BOE-Jeremy-SHV"))
        #expect(text.contains("Invoice date:"))
        #expect(text.contains("Due:"))
        #expect(text.contains("Balance:"))
        #expect(text.contains("Thank you."))
        invoice.closing = "With gratitude."
        let custom = try #require(PDFDocument(data: InvoicePDFRenderer.render(invoice))?.string)
        #expect(custom.contains("With gratitude."))
        #expect(!custom.contains("Thank you."))
    }

    @Test func moneyParsesCents() {
        #expect(ShootQMoney.decimal("1400.00") == Decimal(string: "1400.00")!)
        #expect(ShootQMoney.cents(85) == Decimal(string: "85.00")!)
    }

    @Test func dashboardCashWindowsFollowReceiptDates() throws {
        let calendar = utcCalendar()
        let now = utcDate(calendar, 2026, 10, 23, hour: 15)
        let container = try makeBooksContainer()
        let context = container.mainContext
        let amounts: [(Date, Decimal)] = [
            (utcDate(calendar, 2026, 10, 2), 100),
            (utcDate(calendar, 2026, 10, 23), 40),
            (utcDate(calendar, 2026, 9, 15), 200),
            (utcDate(calendar, 2026, 8, 1), 10),
            (utcDate(calendar, 2026, 5, 15), 7),
            (utcDate(calendar, 2026, 1, 5), 1000),
            (utcDate(calendar, 2025, 12, 20), 999),
            (utcDate(calendar, 2025, 10, 2), 50),
            (utcDate(calendar, 2026, 11, 1, hour: 0), 12_345),
        ]
        let receipts = amounts.map { paidAt, amount in
            PaymentReceipt(paidAt: paidAt, amount: amount)
        }
        for receipt in receipts {
            context.insert(receipt)
        }

        let month = DashboardMath.collectionReport(
            receipts: receipts, window: .month, now: now, calendar: calendar
        )
        let three = DashboardMath.collectionReport(
            receipts: receipts, window: .threeMonths, now: now, calendar: calendar
        )
        let six = DashboardMath.collectionReport(
            receipts: receipts, window: .sixMonths, now: now, calendar: calendar
        )
        let year = DashboardMath.collectionReport(
            receipts: receipts, window: .year, now: now, calendar: calendar
        )

        #expect(month.total == 140)
        #expect(month.priorTotal == 200)
        #expect(month.buckets.count == 5)
        #expect(month.buckets.first?.label == "1–7")
        #expect(month.buckets[3].label == "22–28")
        #expect(month.buckets[3].collected == 40)
        #expect(month.buckets.last?.label == "29–31")
        #expect(month.buckets.reduce(Decimal.zero) { $0 + $1.collected } == month.total)

        let symbols = calendar.shortMonthSymbols
        #expect(three.total == 350)
        #expect(three.priorTotal == 7)
        #expect(three.buckets.map(\.label) == [symbols[7], symbols[8], symbols[9]])
        #expect(three.buckets.reduce(Decimal.zero) { $0 + $1.collected } == three.total)

        #expect(six.total == 357)
        #expect(six.priorTotal == 1999)
        #expect(six.buckets.count == 6)
        #expect(six.buckets.first?.label == symbols[4])

        #expect(year.total == 1357)
        #expect(year.priorTotal == 50)
        #expect(year.buckets.count == 10)
        #expect(year.buckets.map(\.label) == Array(symbols.prefix(10)))
        #expect(year.buckets.reduce(Decimal.zero) { $0 + $1.collected } == year.total)
        #expect(DashboardMath.collectedThisMonth(in: receipts, now: now, calendar: calendar) == 140)
        #expect(DashboardMath.collectedThisYear(in: receipts, now: now, calendar: calendar) == 1357)

        let octoberWeek = DashboardMath.normalizedRange(
            start: utcDate(calendar, 2026, 10, 23),
            end: utcDate(calendar, 2026, 10, 8),
            calendar: calendar
        )
        #expect(
            octoberWeek
                == DashboardMath.normalizedRange(
                    start: utcDate(calendar, 2026, 10, 8),
                    end: utcDate(calendar, 2026, 10, 23),
                    calendar: calendar
                )
        )
        let custom = DashboardMath.collectionReport(
            receipts: receipts, window: .range, range: octoberWeek, now: now, calendar: calendar
        )
        #expect(custom.total == 40)
        #expect(custom.priorTotal == 100)
        #expect(custom.buckets.map(\.label) == ["8–14", "15–21", "22–23"])
        #expect(custom.buckets.map(\.collected) == [0, 0, 40])

        let oneDay = DashboardMath.normalizedRange(
            start: utcDate(calendar, 2026, 10, 2),
            end: utcDate(calendar, 2026, 10, 2),
            calendar: calendar
        )
        let dayReport = DashboardMath.collectionReport(
            receipts: receipts, window: .range, range: oneDay, now: now, calendar: calendar
        )
        #expect(dayReport.total == 100)
        #expect(CollectionWindow.range.spokenTitle(covering: oneDay, calendar: calendar).contains("2026"))

        let lateSummer = DashboardMath.normalizedRange(
            start: utcDate(calendar, 2026, 8, 1),
            end: utcDate(calendar, 2026, 10, 23),
            calendar: calendar
        )
        let summer = DashboardMath.collectionReport(
            receipts: receipts, window: .range, range: lateSummer, now: now, calendar: calendar
        )
        #expect(summer.total == 350)
        #expect(summer.priorTotal == 7)
        #expect(summer.buckets.map(\.label) == [symbols[7], symbols[8], symbols[9]])
        #expect(summer.buckets.reduce(Decimal.zero) { $0 + $1.collected } == summer.total)

        let turnOfYear = DashboardMath.normalizedRange(
            start: utcDate(calendar, 2025, 11, 1),
            end: utcDate(calendar, 2026, 1, 31),
            calendar: calendar
        )
        let acrossYears = DashboardMath.collectionReport(
            receipts: receipts, window: .range, range: turnOfYear, now: now, calendar: calendar
        )
        #expect(acrossYears.total == 1999)
        #expect(acrossYears.buckets.count == 3)
        #expect(acrossYears.buckets.reduce(Decimal.zero) { $0 + $1.collected } == acrossYears.total)
    }

    @Test func dashboardCollectedFilterFollowsTheCash() throws {
        let calendar = utcCalendar()
        let now = utcDate(calendar, 2026, 10, 23, hour: 15)
        let container = try makeBooksContainer()
        let context = container.mainContext
        let earlyOctober = Invoice(number: "2", status: .pending, balance: 10, billToName: "Early")
        let midOctober = Invoice(number: "10", status: .pending, balance: 40, billToName: "Mid")
        let september = Invoice(number: "9", status: .paid, amountPaid: 80, balance: 0, billToName: "Sep")
        let waiting = Invoice(
            number: "1",
            dueDate: Date.distantFuture,
            status: .pending,
            balance: 15,
            billToName: "Wait"
        )
        let late = Invoice(
            number: "8",
            dueDate: Date(timeIntervalSince1970: 0),
            status: .pending,
            balance: 4,
            billToName: "Late"
        )
        for invoice in [earlyOctober, midOctober, september, waiting, late] {
            context.insert(invoice)
        }
        let earlyReceipt = PaymentReceipt(paidAt: utcDate(calendar, 2026, 10, 2), amount: 5)
        earlyReceipt.invoice = earlyOctober
        let midReceipt = PaymentReceipt(paidAt: utcDate(calendar, 2026, 10, 10), amount: 25)
        midReceipt.invoice = midOctober
        let septemberReceipt = PaymentReceipt(paidAt: utcDate(calendar, 2026, 9, 10), amount: 80)
        septemberReceipt.invoice = september
        for receipt in [earlyReceipt, midReceipt, septemberReceipt] {
            context.insert(receipt)
        }
        let invoices = [earlyOctober, midOctober, september, waiting, late]
        let receipts = [earlyReceipt, midReceipt, septemberReceipt]

        let month = DashboardMath.ledgerItems(
            invoices, receipts: receipts, filter: .cash(.month), search: "", now: now, calendar: calendar
        )
        #expect(month.map(\.invoice.number) == ["10", "2"])
        #expect(month.map(\.periodCollected) == [25, 5])

        let three = DashboardMath.ledgerItems(
            invoices, receipts: receipts, filter: .cash(.threeMonths), search: "", now: now, calendar: calendar
        )
        #expect(three.map(\.invoice.number) == ["9", "10", "2"])

        let report = DashboardMath.collectionReport(receipts: receipts, window: .month, now: now, calendar: calendar)
        let midWeek = report.buckets.first { $0.collected == 25 }
        let narrowed = DashboardMath.ledgerItems(
            invoices,
            receipts: receipts,
            filter: .cash(.month, bucketStart: midWeek?.start),
            search: "",
            now: now,
            calendar: calendar
        )
        #expect(narrowed.map(\.invoice.number) == ["10"])

        let earlyOnly = DashboardMath.normalizedRange(
            start: utcDate(calendar, 2026, 10, 1),
            end: utcDate(calendar, 2026, 10, 2),
            calendar: calendar
        )
        let ranged = DashboardMath.ledgerItems(
            invoices,
            receipts: receipts,
            filter: .cash(.range),
            search: "",
            range: earlyOnly,
            now: now,
            calendar: calendar
        )
        #expect(ranged.map(\.invoice.number) == ["2"])
        #expect(ranged.map(\.periodCollected) == [5])

        let waitingOnly = DashboardMath.ledgerItems(
            invoices, filter: .notYetDue, search: "", now: now, calendar: calendar
        )
        #expect(waitingOnly.map(\.invoice.number).contains("1"))
        #expect(!waitingOnly.map(\.invoice.number).contains("8"))
        #expect(DashboardMath.ledgerItems(invoices, filter: .overdue, search: "", now: now).map(\.invoice.number) == ["8"])
    }

    @Test func dashboardInvoicedTotalFollowsTheInvoiceDate() throws {
        let calendar = utcCalendar()
        let now = utcDate(calendar, 2026, 10, 23, hour: 15)
        let container = try makeBooksContainer()
        let context = container.mainContext
        let october = Invoice(
            number: "10",
            invoiceDate: utcDate(calendar, 2026, 10, 2),
            status: .pending,
            total: 100,
            balance: 40,
            billToName: "Oct"
        )
        let draft = Invoice(
            number: "3",
            invoiceDate: utcDate(calendar, 2026, 10, 20),
            status: .draft,
            total: 15,
            billToName: "Draft"
        )
        let september = Invoice(
            number: "9",
            invoiceDate: utcDate(calendar, 2026, 9, 10),
            status: .paid,
            total: 40,
            amountPaid: 40,
            billToName: "Sep"
        )
        let january = Invoice(
            number: "1",
            invoiceDate: utcDate(calendar, 2026, 1, 5),
            status: .paid,
            total: 7,
            amountPaid: 7,
            billToName: "Jan"
        )
        let lastYear = Invoice(
            number: "8",
            invoiceDate: utcDate(calendar, 2025, 10, 2),
            status: .paid,
            total: 50,
            amountPaid: 50,
            billToName: "Old"
        )
        let voided = Invoice(
            number: "4",
            invoiceDate: utcDate(calendar, 2026, 10, 8),
            status: .void,
            total: 999,
            billToName: "Void"
        )
        let invoices = [october, draft, september, january, lastYear, voided]
        for invoice in invoices {
            context.insert(invoice)
        }

        #expect(DashboardMath.invoiced(in: invoices, window: .month, now: now, calendar: calendar) == 115)
        #expect(DashboardMath.invoiced(in: invoices, window: .threeMonths, now: now, calendar: calendar) == 155)
        #expect(DashboardMath.invoiced(in: invoices, window: .year, now: now, calendar: calendar) == 162)

        let month = DashboardMath.ledgerItems(
            invoices, filter: .issued(.month), search: "", now: now, calendar: calendar
        )
        #expect(month.map(\.invoice.number) == ["3", "10"])
        #expect(month.map(\.showsInvoiceTotal) == [true, true])
        #expect(month.map(\.invoice.total) == [15, 100])

        let three = DashboardMath.ledgerItems(
            invoices, filter: .issued(.threeMonths), search: "", now: now, calendar: calendar
        )
        #expect(three.map(\.invoice.number) == ["3", "10", "9"])

        let septemberOnly = DashboardMath.normalizedRange(
            start: utcDate(calendar, 2026, 9, 1),
            end: utcDate(calendar, 2026, 9, 30),
            calendar: calendar
        )
        #expect(
            DashboardMath.invoiced(
                in: invoices, window: .range, range: septemberOnly, now: now, calendar: calendar
            ) == 40
        )
        let ranged = DashboardMath.ledgerItems(
            invoices,
            filter: .issued(.range),
            search: "",
            range: septemberOnly,
            now: now,
            calendar: calendar
        )
        #expect(ranged.map(\.invoice.number) == ["9"])
    }

    @Test func dashboardOpenBookSplitsOverdueFromCurrent() throws {
        let container = try makeBooksContainer()
        let context = container.mainContext
        let late = Invoice(
            number: "1",
            dueDate: Date(timeIntervalSince1970: 0),
            status: .pending,
            balance: 300
        )
        let pending = Invoice(
            number: "2",
            dueDate: Date.distantFuture,
            status: .pending,
            balance: 50
        )
        let draft = Invoice(number: "5", status: .draft, balance: 15)
        let paid = Invoice(number: "3", status: .paid, total: 80, amountPaid: 80, balance: 0)
        let voided = Invoice(number: "4", status: .void, balance: 999)
        let invoices = [late, pending, draft, paid, voided]
        for invoice in invoices {
            context.insert(invoice)
        }

        let book = DashboardMath.openBook(in: invoices)
        #expect(book.overdue == 300)
        #expect(book.current == 65)
        #expect(book.total == 365)
        #expect(book.total == DashboardMath.openBalance(in: invoices))
    }

    @Test func openCustomersGroupByNameAndDropOutOfTheTotal() throws {
        let container = try makeBooksContainer()
        let context = container.mainContext
        let ada = Invoice(number: "1", dueDate: .distantFuture, status: .pending, balance: 10, billToName: "Ada")
        let adaAgain = Invoice(number: "2", dueDate: .distantFuture, status: .pending, balance: 15, billToName: "ada")
        let bea = Invoice(
            number: "3",
            dueDate: Date(timeIntervalSince1970: 0),
            status: .pending,
            balance: 40,
            billToName: "Bea"
        )
        let paid = Invoice(number: "4", status: .paid, balance: 0, billToName: "Cara")
        let invoices = [ada, adaAgain, bea, paid]
        for invoice in invoices {
            context.insert(invoice)
        }

        let adaKey = DashboardMath.customerKey(for: ada)
        #expect(adaKey == DashboardMath.customerKey(for: adaAgain))

        let customers = DashboardMath.openCustomers(in: invoices)
        #expect(customers.map(\.name) == ["Ada", "Bea"])
        #expect(customers.map(\.balance) == [25, 40])

        let book = DashboardMath.openBook(in: invoices, excluding: [adaKey])
        #expect(book.current == 0)
        #expect(book.overdue == 40)
        #expect(book.total == 40)
        #expect(DashboardMath.openBook(in: invoices).total == 65)
        #expect(DashboardMath.openCustomers(in: [paid]).isEmpty)
    }

    @Test func dashboardLedgerLeadsWithTheSoonestDueDate() throws {
        let container = try makeBooksContainer()
        let context = container.mainContext
        let sooner = Invoice(
            number: "1",
            dueDate: Date.now.addingTimeInterval(86_400),
            status: .pending,
            balance: 10,
            billToName: "Ada"
        )
        let later = Invoice(
            number: "2",
            dueDate: Date.now.addingTimeInterval(86_400 * 9),
            status: .pending,
            balance: 80,
            billToName: "Bea"
        )
        let late = Invoice(
            number: "9",
            dueDate: Date(timeIntervalSince1970: 0),
            status: .pending,
            balance: 4,
            billToName: "Late"
        )
        let voided = Invoice(number: "5", status: .void, balance: 30, billToName: "Void")
        let blank = Invoice(shootqID: "1234867", number: "", status: .pending, balance: 5, billToName: "Snow")
        for invoice in [later, sooner, late, voided, blank] {
            context.insert(invoice)
        }

        let open = DashboardMath.ledgerItems([later, sooner, late, voided, blank], filter: .open, search: "")
        #expect(open.map(\.invoice.number) == ["9", "1", "2", ""])
        #expect(open.map(\.invoice.billToName) == ["Late", "Ada", "Bea", "Snow"])
        #expect(DashboardMath.ledgerItems([later, sooner], filter: .open, search: "bea").map(\.invoice.number) == ["2"])
        #expect(DashboardMath.ledgerItems([sooner, late], filter: .overdue, search: "").map(\.invoice.number) == ["9"])
        #expect(DashboardMath.ledgerItems([sooner, late], filter: .notYetDue, search: "").map(\.invoice.number) == ["1"])
        #expect(DashboardMath.ledgerItems([voided], filter: .open, search: "").isEmpty)
        #expect(DashboardMath.ledgerItems([voided], filter: .all, search: "").count == 1)
        #expect(DashboardMath.ledgerItems([blank], filter: .open, search: "1234867").map(\.invoice.billToName) == ["Snow"])
    }

    @Test func cashFlowPlacesOpenBalancesOnTheMonthTheyAreDue() throws {
        let container = try makeBooksContainer()
        let context = container.mainContext
        let calendar = utcCalendar()
        let now = utcDate(calendar, 2026, 10, 24)
        let thisMonth = Invoice(
            number: "1",
            dueDate: utcDate(calendar, 2026, 10, 28),
            status: .pending,
            balance: 100
        )
        let overdue = Invoice(
            number: "2",
            dueDate: utcDate(calendar, 2026, 9, 1),
            status: .pending,
            balance: 40
        )
        let undated = Invoice(number: "3", status: .pending, balance: 5)
        let november = Invoice(
            number: "4",
            dueDate: utcDate(calendar, 2026, 11, 15),
            status: .pending,
            balance: 20
        )
        let december = Invoice(
            number: "10",
            dueDate: utcDate(calendar, 2026, 12, 2),
            status: .draft,
            balance: 8
        )
        let yesterday = Invoice(
            number: "8",
            dueDate: utcDate(calendar, 2026, 10, 23),
            status: .pending,
            balance: 3
        )
        let far = Invoice(
            number: "5",
            dueDate: utcDate(calendar, 2027, 8, 1),
            status: .pending,
            balance: 7
        )
        let paid = Invoice(
            number: "6",
            dueDate: utcDate(calendar, 2026, 10, 2),
            status: .paid,
            balance: 0
        )
        let voided = Invoice(
            number: "7",
            dueDate: utcDate(calendar, 2026, 10, 2),
            status: .void,
            balance: 999
        )
        let invoices = [thisMonth, overdue, undated, november, december, yesterday, far, paid, voided]
        for invoice in invoices {
            context.insert(invoice)
        }

        let report = DashboardMath.cashFlow(in: invoices, now: now, calendar: calendar)
        #expect(report.months.map(\.label) == ["Oct", "Nov", "Dec", "Jan ’27", "Feb", "Mar"])
        #expect(report.months.map(\.expected) == [148, 20, 8, 0, 0, 0])
        #expect(report.thisMonth == 148)
        #expect(report.pastDue == 43)
        #expect(report.later == 7)
        #expect(report.horizonTotal + report.later == DashboardMath.openBalance(in: invoices))

        let october = DashboardMath.ledgerItems(
            invoices,
            filter: .expected(report.months[0].start),
            search: "",
            now: now,
            calendar: calendar
        )
        #expect(october.map(\.invoice.number) == ["2", "8", "1", "3"])

        let wholeForecast = DashboardMath.ledgerItems(
            invoices,
            filter: .expected(nil),
            search: "",
            now: now,
            calendar: calendar
        )
        #expect(wholeForecast.count == 7)
    }

    @Test func dashboardComparisonSpeaksInPlainLanguage() {
        #expect(DashboardMath.percentChange(current: 200, prior: 100) == 1)
        #expect(DashboardMath.percentChange(current: 50, prior: 100) == -0.5)
        #expect(DashboardMath.percentChange(current: 10, prior: 0) == nil)
        #expect(DashboardMath.comparisonCaption(current: 0, prior: 0, window: .year) == nil)
        #expect(
            DashboardMath.comparisonCaption(current: 10, prior: 0, window: .month)
                == "Nothing collected in the prior month"
        )
        #expect(
            DashboardMath.comparisonCaption(current: 100, prior: 100, window: .sixMonths)
                == "Even with the prior 6 months"
        )
        let up = DashboardMath.comparisonCaption(current: 200, prior: 100, window: .threeMonths)
        #expect(up?.contains("above") == true)
        #expect(up?.contains("prior 3 months") == true)
        let down = DashboardMath.comparisonCaption(current: 40, prior: 80, window: .year)
        #expect(down?.contains("below") == true)
        #expect(down?.contains("prior year") == true)
        #expect(
            DashboardMath.comparisonCaption(current: 10, prior: 0, window: .range)
                == "Nothing collected in the prior period"
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func utcDate(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func writeVersion1Invoice(at storeURL: URL) throws {
        let schema = Schema(versionedSchema: StudioSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let invoice = Invoice(
            shootqID: "1849451",
            number: "1849451",
            status: .pending,
            total: Decimal(string: "4386.61")!,
            balance: Decimal(string: "4386.61")!,
            billToName: "Snow Companies",
            isImported: true
        )
        container.mainContext.insert(invoice)
        try container.mainContext.save()
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suite = "BigQ.JobTypeCatalog.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeBooksContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StudioSchemaV5.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
