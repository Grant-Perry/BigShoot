import Foundation
import SwiftData
import Testing
@testable import BigShoot

@MainActor
struct BigShootTests {
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

    @Test func nextNumberClearsTheHighestImported() {
        #expect(InvoiceMath.nextNumber(among: ["84409", "", "12"]) == "84410")
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
            .appendingPathComponent("Xcode/BigShoot/shootq-export", isDirectory: true)
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
        let storeURL = folder.appendingPathComponent("BigShoot.store")
        try writeVersion1Invoice(at: storeURL)

        let schema = Schema(versionedSchema: StudioSchemaV2.self)
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

    @Test func moneyParsesCents() {
        #expect(ShootQMoney.decimal("1400.00") == Decimal(string: "1400.00")!)
        #expect(ShootQMoney.cents(85) == Decimal(string: "85.00")!)
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

    private func makeBooksContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StudioSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
