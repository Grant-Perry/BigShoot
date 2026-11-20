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

    @Test func quoteRoundTripRestoresThePayLinkAgreementAndTerms() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let contact = Contact(fullName: "Ada Lovelace", email: "ada@north.test", createdAt: when)
        let studio = StudioBrand(name: "North Light", isPrimary: true, createdAt: when)
        let job = Job(name: "Wedding", eventDate: when, contact: contact)
        job.paymentScheduleModeRaw = QuotePaymentScheduleMode.scheduled.rawValue
        let jobTerm = JobPaymentTerm(
            title: "Retainer",
            position: 0,
            amountMode: .percentOfTotal,
            percent: 50,
            dueMode: .signature
        )
        jobTerm.job = job
        let catalog = CatalogItem(name: "Album", defaultPrice: 1200, taxable: true)
        let invoice = Invoice(number: "1042", invoiceDate: when, total: 1200, balance: 1200, billToName: "Ada Lovelace")
        invoice.payToken = "inv-pay"
        invoice.contact = contact
        invoice.job = job
        invoice.studio = studio
        let quote = Quote(
            number: "Q-1042",
            quoteDate: when,
            status: .signed,
            total: 1200,
            billToName: "Ada Lovelace",
            note: "Balcony",
            closing: "With thanks",
            agreementTitle: "Wedding Agreement",
            agreementHTML: "<p>Signed terms</p>",
            sentAt: when,
            signedAt: when
        )
        quote.payToken = "quote-pay"
        quote.paymentScheduleModeRaw = QuotePaymentScheduleMode.scheduled.rawValue
        quote.signedEvidenceData = Data("signed-pdf".utf8)
        quote.contact = contact
        quote.job = job
        quote.studio = studio
        quote.convertedInvoice = invoice
        let line = QuoteLine(name: "Album", quantity: 1, unitPrice: 1200, taxable: true)
        line.catalogItem = catalog
        line.quote = quote
        let term = QuotePaymentTerm(
            title: "Retainer",
            position: 0,
            amountMode: .percentOfTotal,
            percent: 50,
            dueMode: .signature,
            amount: 600
        )
        term.quote = quote
        let groom = Contact(fullName: "Charles Babbage", email: "charles@north.test", createdAt: when)
        job.bride = contact
        job.groom = groom
        let quoteKey = QuoteMailKey.ensure(for: quote)
        let letter = QuoteEmail(
            quoteKey: quoteKey,
            recipient: "ada@north.test",
            subject: "Your quote",
            body: "Hello Ada",
            templateName: "Proposal"
        )
        letter.state = .sent
        letter.sentAt = when
        letter.payURL = "https://bigq-pay.web.app/pay/abc"
        letter.postmarkMessageID = "pm-1"
        let mailTemplate = EmailTemplate(name: "Proposal", subject: "Quote [Quote Number]", body: "Dear [Client Name]")
        for model in [studio, contact, groom, job, jobTerm, catalog, invoice, quote, line, term, letter, mailTemplate] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        let folder = temporaryPackage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let written = try BackupExport.write(context: context, scope: .full, defaults: isolatedDefaults(), to: folder, createdAt: when)
        #expect(written.counts.quotes == 1)
        #expect(written.bodiesWritten == 1)

        let destination = try makeContainer()
        let payload = try BackupPackage.load(at: folder)
        _ = try BackupRestore.apply(payload, mode: .replace, context: destination.mainContext, defaults: isolatedDefaults())

        let restored = try #require(try destination.mainContext.fetch(FetchDescriptor<Quote>()).first)
        #expect(restored.number == "Q-1042")
        #expect(restored.payToken == "quote-pay")
        #expect(restored.note == "Balcony")
        #expect(restored.closing == "With thanks")
        #expect(restored.agreementHTML == "<p>Signed terms</p>")
        #expect(restored.signedEvidenceData == Data("signed-pdf".utf8))
        #expect(restored.paymentScheduleModeRaw == QuotePaymentScheduleMode.scheduled.rawValue)
        #expect(restored.contact?.email == "ada@north.test")
        #expect(restored.job?.name == "Wedding")
        #expect(restored.studio?.name == "North Light")
        #expect(restored.convertedInvoice?.number == "1042")
        #expect(restored.convertedInvoice?.payToken == "inv-pay")
        #expect(restored.lines.first?.catalogItem?.name == "Album")
        #expect(restored.lines.first?.unitPrice == 1200)
        #expect(restored.paymentTerms.first?.title == "Retainer")
        #expect(restored.paymentTerms.first?.percent == 50)
        #expect(restored.paymentTerms.first?.amount == 600)
        let jobs = try destination.mainContext.fetch(FetchDescriptor<Job>())
        #expect(jobs.first?.paymentScheduleModeRaw == QuotePaymentScheduleMode.scheduled.rawValue)
        #expect(jobs.first?.paymentTerms.first?.title == "Retainer")
        #expect(jobs.first?.paymentTerms.first?.percent == 50)
        #expect(jobs.first?.bride?.email == "ada@north.test")
        #expect(jobs.first?.groom?.fullName == "Charles Babbage")
        let letters = try destination.mainContext.fetch(FetchDescriptor<QuoteEmail>())
        #expect(letters.count == 1)
        #expect(letters.first?.subject == "Your quote")
        #expect(letters.first?.body == "Hello Ada")
        #expect(letters.first?.postmarkMessageID == "pm-1")
        #expect(letters.first?.quoteKey == restored.archiveID)
        let mailTemplates = try destination.mainContext.fetch(FetchDescriptor<EmailTemplate>())
        #expect(mailTemplates.count == 1)
        #expect(mailTemplates.first?.body == "Dear [Client Name]")
    }

    @Test func mergeUpdatesQuotesAndTemplatesThatDoNotShareArchiveIDs() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let invoice = Invoice(number: "1042", total: 1200, balance: 1200, billToName: "Ada Lovelace")
        let quote = Quote(number: "Q-9", total: 1200, billToName: "Ada Lovelace", agreementHTML: "<p>Terms</p>")
        quote.payToken = "quote-pay"
        quote.convertedInvoice = invoice
        let template = Contract(title: "Wedding Agreement", html: "<p>Template</p>", isTemplate: true)
        let letter = QuoteEmail(quoteKey: QuoteMailKey.ensure(for: quote), subject: "Hello", body: "Terms enclosed")
        let saved = EmailTemplate(name: "Proposal", subject: "Hi", body: "Body")
        sourceContext.insert(invoice)
        sourceContext.insert(quote)
        sourceContext.insert(template)
        sourceContext.insert(letter)
        sourceContext.insert(saved)
        try sourceContext.save()

        let folder = temporaryPackage()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try BackupExport.write(context: sourceContext, scope: .full, defaults: isolatedDefaults(), to: folder)

        let destination = try makeContainer()
        let context = destination.mainContext
        let localInvoice = Invoice(number: "1042", total: 1, balance: 1)
        localInvoice.archiveID = "local-invoice"
        let localQuote = Quote(number: "Q-9", total: 1)
        localQuote.archiveID = "local-quote"
        let localTemplate = Contract(title: "Wedding Agreement", html: "old", isTemplate: true)
        localTemplate.archiveID = "local-template"
        let kept = Quote(number: "LOCAL", total: 5)
        let localMail = EmailTemplate(name: "Proposal", subject: "old", body: "old")
        context.insert(localInvoice)
        context.insert(localQuote)
        context.insert(localTemplate)
        context.insert(kept)
        context.insert(localMail)
        try context.save()

        let payload = try BackupPackage.load(at: folder)
        _ = try BackupRestore.apply(payload, mode: .merge, context: context, defaults: isolatedDefaults())

        let quotes = try context.fetch(FetchDescriptor<Quote>())
        #expect(quotes.count == 2)
        let restored = try #require(quotes.first { $0.number == "Q-9" })
        #expect(restored.payToken == "quote-pay")
        #expect(restored.agreementHTML == "<p>Terms</p>")
        #expect(restored.convertedInvoice?.number == "1042")
        #expect(restored.convertedInvoice?.archiveID == "local-invoice")
        #expect(quotes.contains { $0.number == "LOCAL" })
        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        #expect(invoices.count == 1)
        let contracts = try context.fetch(FetchDescriptor<Contract>())
        #expect(contracts.count == 1)
        #expect(contracts.first?.html == "<p>Template</p>")
        #expect(contracts.first?.archiveID == "local-template")
        let letters = try context.fetch(FetchDescriptor<QuoteEmail>())
        #expect(letters.count == 1)
        #expect(letters.first?.quoteKey == "local-quote")
        #expect(letters.first?.body == "Terms enclosed")
        let mailTemplates = try context.fetch(FetchDescriptor<EmailTemplate>())
        #expect(mailTemplates.count == 1)
        #expect(mailTemplates.first?.body == "Body")
    }

    @Test func invoiceLettersAndAttachmentsRoundTrip() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let invoice = Invoice(number: "1042", total: 100, balance: 80, billToName: "Ada Lovelace")
        let quote = Quote(number: "Q-1", total: 100, billToName: "Ada Lovelace")
        let invoiceLetter = InvoiceEmail(
            invoiceKey: InvoiceMailKey.ensure(for: invoice),
            recipient: "ada@north.test",
            subject: "Invoice 1042",
            body: "Please pay"
        )
        let quoteLetter = QuoteEmail(
            quoteKey: QuoteMailKey.ensure(for: quote),
            subject: "Your quote",
            body: "Hello"
        )
        let invoiceFile = MailAttachment(fileName: "notes.pdf", contentType: "application/pdf", bytes: Data("pdf-bytes".utf8))
        invoiceFile.invoiceEmail = invoiceLetter
        let quoteFile = MailAttachment(fileName: "extra.jpg", contentType: "image/jpeg", bytes: Data("jpg".utf8))
        quoteFile.quoteEmail = quoteLetter
        for model in [invoice, quote, invoiceLetter, quoteLetter, invoiceFile, quoteFile] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        let folder = temporaryPackage()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try BackupExport.write(context: context, scope: .full, defaults: isolatedDefaults(), to: folder)

        let destination = try makeContainer()
        let payload = try BackupPackage.load(at: folder)
        _ = try BackupRestore.apply(payload, mode: .replace, context: destination.mainContext, defaults: isolatedDefaults())

        let letters = try destination.mainContext.fetch(FetchDescriptor<InvoiceEmail>())
        let restoredLetter = try #require(letters.first)
        #expect(restoredLetter.subject == "Invoice 1042")
        #expect(restoredLetter.body == "Please pay")
        #expect(restoredLetter.files.count == 1)
        #expect(restoredLetter.files.first?.fileName == "notes.pdf")
        #expect(restoredLetter.files.first?.bytes == Data("pdf-bytes".utf8))
        let restoredInvoice = try #require(try destination.mainContext.fetch(FetchDescriptor<Invoice>()).first)
        #expect(restoredLetter.invoiceKey == restoredInvoice.archiveID)

        let quoteLetters = try destination.mainContext.fetch(FetchDescriptor<QuoteEmail>())
        let restoredQuoteLetter = try #require(quoteLetters.first { $0.subject == "Your quote" })
        #expect(restoredQuoteLetter.files.count == 1)
        #expect(restoredQuoteLetter.files.first?.bytes == Data("jpg".utf8))
    }

    @Test func catalogReplaceRelinksQuoteLines() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let catalog = CatalogItem(name: "Album", defaultPrice: 100, detail: "Leather")
        let quote = Quote(number: "Q-1", total: 100, billToName: "Ada Lovelace")
        let line = QuoteLine(name: "Album", quantity: 1, unitPrice: 100)
        line.catalogItem = catalog
        line.quote = quote
        context.insert(catalog)
        context.insert(quote)
        context.insert(line)
        try context.save()

        let folder = temporaryPackage()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try BackupExport.write(context: context, scope: .catalog, defaults: isolatedDefaults(), to: folder)
        catalog.defaultPrice = 5
        try context.save()

        let payload = try BackupPackage.load(at: folder)
        _ = try BackupRestore.apply(payload, mode: .replace, context: context, defaults: isolatedDefaults())

        let quotes = try context.fetch(FetchDescriptor<Quote>())
        #expect(quotes.count == 1)
        #expect(quotes.first?.number == "Q-1")
        let items = try context.fetch(FetchDescriptor<CatalogItem>())
        #expect(items.count == 1)
        #expect(items[0].defaultPrice == 100)
        #expect(quotes.first?.lines.first?.catalogItem?.name == "Album")
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
        let schema = Schema(versionedSchema: StudioSchemaV17.self)
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
