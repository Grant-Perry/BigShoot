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
        var contracts: Int
        var events: Int

        func sentence(for scope: BackupScope) -> String {
            switch scope {
            case .full:
                BackupList.sentence([
                    BackupList.count(studios, "studio", "studios"),
                    BackupList.count(contacts, "client", "clients"),
                    BackupList.count(jobs, "job", "jobs"),
                    BackupList.count(invoices, "invoice", "invoices"),
                    BackupList.count(catalog, "catalog item", "catalog items"),
                    BackupList.count(contracts, "contract", "contracts"),
                ])
            case .books:
                BackupList.sentence([
                    BackupList.count(studios, "studio", "studios"),
                    BackupList.count(contacts, "client", "clients"),
                    BackupList.count(jobs, "job", "jobs"),
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
