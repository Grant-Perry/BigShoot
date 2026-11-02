import Foundation

/// The books inside a backup folder. Agreement HTML and logo bytes live beside this file.
struct BackupFile: Codable, Sendable, Equatable {
    var format: Int
    var scope: String
    var createdAt: Date
    var studios: [Studio]
    var contacts: [Contact]
    var jobs: [Job]
    var catalog: [CatalogItem]
    var taxSchedules: [TaxSchedule]
    var invoices: [Invoice]
    var quotes: [Quote]
    var contracts: [Contract]
    var events: [BooksEvent]
    var preferences: BackupPreferences?

    enum CodingKeys: String, CodingKey {
        case format, scope, createdAt, studios, contacts, jobs, catalog, taxSchedules
        case invoices, quotes, contracts, events, preferences
    }

    init(
        format: Int,
        scope: String,
        createdAt: Date,
        studios: [Studio],
        contacts: [Contact],
        jobs: [Job],
        catalog: [CatalogItem],
        taxSchedules: [TaxSchedule],
        invoices: [Invoice],
        quotes: [Quote] = [],
        contracts: [Contract],
        events: [BooksEvent],
        preferences: BackupPreferences?
    ) {
        self.format = format
        self.scope = scope
        self.createdAt = createdAt
        self.studios = studios
        self.contacts = contacts
        self.jobs = jobs
        self.catalog = catalog
        self.taxSchedules = taxSchedules
        self.invoices = invoices
        self.quotes = quotes
        self.contracts = contracts
        self.events = events
        self.preferences = preferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(Int.self, forKey: .format)
        scope = try container.decode(String.self, forKey: .scope)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        studios = try container.decode([Studio].self, forKey: .studios)
        contacts = try container.decode([Contact].self, forKey: .contacts)
        jobs = try container.decode([Job].self, forKey: .jobs)
        catalog = try container.decode([CatalogItem].self, forKey: .catalog)
        taxSchedules = try container.decode([TaxSchedule].self, forKey: .taxSchedules)
        invoices = try container.decode([Invoice].self, forKey: .invoices)
        quotes = try container.decodeIfPresent([Quote].self, forKey: .quotes) ?? []
        contracts = try container.decode([Contract].self, forKey: .contracts)
        events = try container.decode([BooksEvent].self, forKey: .events)
        preferences = try container.decodeIfPresent(BackupPreferences.self, forKey: .preferences)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(scope, forKey: .scope)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(studios, forKey: .studios)
        try container.encode(contacts, forKey: .contacts)
        try container.encode(jobs, forKey: .jobs)
        try container.encode(catalog, forKey: .catalog)
        try container.encode(taxSchedules, forKey: .taxSchedules)
        try container.encode(invoices, forKey: .invoices)
        try container.encode(quotes, forKey: .quotes)
        try container.encode(contracts, forKey: .contracts)
        try container.encode(events, forKey: .events)
        try container.encodeIfPresent(preferences, forKey: .preferences)
    }

    struct Studio: Codable, Sendable, Equatable {
        var archiveID: String
        var name: String
        var email: String
        var phone: String
        var address: String
        var isPrimary: Bool
        var archived: Bool
        var createdAt: Date
        var logoFile: String?
        var logoSourceFile: String?
    }

    struct Contact: Codable, Sendable, Equatable {
        var archiveID: String
        var shootqID: String?
        var firstName: String
        var lastName: String
        var fullName: String
        var companyName: String
        var email: String
        var phone: String
        var address: String
        var anniversary: Date?
        var archived: Bool
        var createdAt: Date
    }

    struct Job: Codable, Sendable, Equatable {
        var archiveID: String
        var shootqID: String?
        var name: String
        var eventDate: Date?
        var jobType: String
        var status: String
        var archived: Bool
        var contactID: String?
    }

    struct CatalogItem: Codable, Sendable, Equatable {
        var archiveID: String
        var name: String
        var defaultPrice: String
        var detail: String
        var taxable: Bool?
        var timesUsed: Int
    }

    struct TaxSchedule: Codable, Sendable, Equatable {
        var archiveID: String
        var name: String
        var rate: String
    }

    struct Invoice: Codable, Sendable, Equatable {
        var archiveID: String
        var shootqID: String?
        var number: String
        var invoiceDate: Date
        var dueDate: Date?
        var paidDate: Date?
        var status: String
        var tax: String
        var taxRate: String?
        var taxScheduleName: String?
        var invoiceTaxable: Bool?
        var discount: String
        var shipping: String
        var total: String
        var amountPaid: String
        var balance: String
        var collectManually: Bool
        var remindersDisabled: Bool
        var billToName: String
        var note: String
        var closing: String
        var submittedAt: Date?
        var isImported: Bool
        var contactID: String?
        var jobID: String?
        var studioID: String?
        var lines: [Line]
        var schedule: [ScheduleEntry]
        var receipts: [Receipt]
    }

    struct Line: Codable, Sendable, Equatable {
        var shootqID: String?
        var name: String
        var detail: String
        var quantity: String
        var unitPrice: String
        var position: Int
        var packageName: String
        var taxable: Bool?
        var catalogID: String?
    }

    struct ScheduleEntry: Codable, Sendable, Equatable {
        var shootqID: String?
        var due: Date?
        var amount: String
        var amountPaid: String
        var balance: String
        var status: String
    }

    struct Receipt: Codable, Sendable, Equatable {
        var shootqID: String?
        var paidAt: Date
        var amount: String
        var method: String
    }

    struct Quote: Codable, Sendable, Equatable {
        var archiveID: String
        var number: String
        var quoteDate: Date
        var validUntil: Date?
        var status: String
        var tax: String
        var taxRate: String?
        var taxScheduleName: String?
        var invoiceTaxable: Bool?
        var discount: String
        var shipping: String
        var total: String
        var billToName: String
        var note: String
        var closing: String
        var agreementTitle: String
        var sentAt: Date?
        var signedAt: Date?
        var contactID: String?
        var jobID: String?
        var studioID: String?
        var invoiceID: String?
        /// SHA-256 of the agreement HTML.
        var agreementBodyFile: String?
        /// SHA-256 of the returned signed PDF, when present.
        var evidenceFile: String?
        var lines: [Line]
    }

    struct Contract: Codable, Sendable, Equatable {
        var archiveID: String
        var shootqID: String?
        var title: String
        var status: String
        var eventLabel: String
        var sentAt: Date?
        var isTemplate: Bool?
        var jobID: String?
        /// SHA-256 of the agreement HTML. The bytes are `bodies/<hash>.html`.
        var bodyFile: String?
        var signatures: [Signature]
    }

    struct Signature: Codable, Sendable, Equatable {
        var displayName: String
        var completed: Bool
        var signedAt: Date?
        var ipAddress: String
        var shootqContactID: String?
        var contactID: String?
    }

    struct BooksEvent: Codable, Sendable, Equatable {
        var archiveID: String
        var occurredAt: Date
        var kind: String
        var invoiceKey: String
        var invoiceNumber: String
        var clientName: String
        var amount: String
        var detail: String
    }

    var counts: BackupManifest.Counts {
        BackupManifest.Counts(
            studios: studios.count,
            contacts: contacts.count,
            jobs: jobs.count,
            catalog: catalog.count,
            taxSchedules: taxSchedules.count,
            invoices: invoices.count,
            quotes: quotes.count,
            contracts: contracts.count,
            events: events.count
        )
    }
}

/// In-memory backup, including agreement and logo bytes that are stored as side files.
struct BackupPayload: Sendable {
    var file: BackupFile
    var bodies: [String: Data]
    var media: [String: Data]
}

struct BackupWriteResult: Sendable, Equatable {
    var counts: BackupManifest.Counts
    var bodiesWritten: Int
    var bodiesSkipped: Int
}
