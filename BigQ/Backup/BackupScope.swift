import Foundation

/// What a backup folder contains. Restore follows the scope written in the folder.
enum BackupScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case full
    case books
    case catalog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: "Full studio"
        case .books: "Books"
        case .catalog: "Catalog"
        }
    }

    var detail: String {
        switch self {
        case .full: "Studios, clients, jobs, invoices, payments, contracts, the price list, and preferences."
        case .books: "Clients, jobs, invoices, payments, studios, and contracts."
        case .catalog: "The price list and tax schedules."
        }
    }

    var fileToken: String {
        switch self {
        case .full: "Full"
        case .books: "Books"
        case .catalog: "Catalog"
        }
    }

    var includesBooks: Bool { self != .catalog }
    var includesCatalog: Bool { self != .books }
    var includesPreferences: Bool { self == .full }

    /// What a replace of this scope leaves alone.
    var replaceKeeps: String? {
        switch self {
        case .full: nil
        case .books: "The price list stays."
        case .catalog: "Clients, jobs, invoices, and contracts stay."
        }
    }
}
