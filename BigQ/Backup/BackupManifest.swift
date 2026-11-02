import Foundation

struct BackupManifest: Codable, Sendable, Equatable {
    var format: Int
    var scope: String
    var createdAt: Date
    var counts: Counts

    struct Counts: Codable, Sendable, Equatable {
        var studios: Int
        var contacts: Int
        var jobs: Int
        var catalog: Int
        var taxSchedules: Int
        var invoices: Int
        var quotes: Int
        var contracts: Int
        var events: Int

        enum CodingKeys: String, CodingKey {
            case studios, contacts, jobs, catalog, taxSchedules, invoices, quotes, contracts, events
        }

        init(
            studios: Int,
            contacts: Int,
            jobs: Int,
            catalog: Int,
            taxSchedules: Int,
            invoices: Int,
            quotes: Int = 0,
            contracts: Int,
            events: Int
        ) {
            self.studios = studios
            self.contacts = contacts
            self.jobs = jobs
            self.catalog = catalog
            self.taxSchedules = taxSchedules
            self.invoices = invoices
            self.quotes = quotes
            self.contracts = contracts
            self.events = events
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            studios = try container.decode(Int.self, forKey: .studios)
            contacts = try container.decode(Int.self, forKey: .contacts)
            jobs = try container.decode(Int.self, forKey: .jobs)
            catalog = try container.decode(Int.self, forKey: .catalog)
            taxSchedules = try container.decode(Int.self, forKey: .taxSchedules)
            invoices = try container.decode(Int.self, forKey: .invoices)
            quotes = try container.decodeIfPresent(Int.self, forKey: .quotes) ?? 0
            contracts = try container.decode(Int.self, forKey: .contracts)
            events = try container.decode(Int.self, forKey: .events)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(studios, forKey: .studios)
            try container.encode(contacts, forKey: .contacts)
            try container.encode(jobs, forKey: .jobs)
            try container.encode(catalog, forKey: .catalog)
            try container.encode(taxSchedules, forKey: .taxSchedules)
            try container.encode(invoices, forKey: .invoices)
            try container.encode(quotes, forKey: .quotes)
            try container.encode(contracts, forKey: .contracts)
            try container.encode(events, forKey: .events)
        }

        func sentence(for scope: BackupScope) -> String {
            switch scope {
            case .full:
                BackupList.sentence([
                    BackupList.count(studios, "studio", "studios"),
                    BackupList.count(contacts, "client", "clients"),
                    BackupList.count(jobs, "job", "jobs"),
                    BackupList.count(quotes, "quote", "quotes"),
                    BackupList.count(invoices, "invoice", "invoices"),
                    BackupList.count(catalog, "catalog item", "catalog items"),
                    BackupList.count(contracts, "contract", "contracts"),
                ])
            case .books:
                BackupList.sentence([
                    BackupList.count(studios, "studio", "studios"),
                    BackupList.count(contacts, "client", "clients"),
                    BackupList.count(jobs, "job", "jobs"),
                    BackupList.count(quotes, "quote", "quotes"),
                    BackupList.count(invoices, "invoice", "invoices"),
                    BackupList.count(contracts, "contract", "contracts"),
                ])
            case .catalog:
                BackupList.sentence([
                    BackupList.count(catalog, "catalog item", "catalog items"),
                    BackupList.count(taxSchedules, "tax schedule", "tax schedules"),
                ])
            }
        }
    }
}

enum BackupList {
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    static func sentence(_ parts: [String]) -> String {
        switch parts.count {
        case 0:
            return "nothing"
        case 1:
            return parts[0]
        case 2:
            return "\(parts[0]) and \(parts[1])"
        default:
            let head = parts.dropLast().joined(separator: ", ")
            return "\(head), and \(parts[parts.count - 1])"
        }
    }
}
