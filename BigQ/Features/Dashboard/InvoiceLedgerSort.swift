import Foundation

/// How the dashboard invoice list is ordered.
enum InvoiceLedgerSort: String, CaseIterable, Identifiable, Hashable {
    case client
    case invoiceDate
    case due
    case amount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .client: "Client"
        case .invoiceDate: "Invoice date"
        case .due: "Days"
        case .amount: "Amount"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .client: "Client"
        case .invoiceDate: "Invoice date"
        case .due: "Days until due or past due"
        case .amount: "Amount due"
        }
    }

    /// Direction chosen when this key is selected.
    var defaultAscending: Bool {
        switch self {
        case .client, .due: true
        case .invoiceDate, .amount: false
        }
    }

    func directionPhrase(ascending: Bool) -> String {
        switch self {
        case .client:
            ascending ? "A to Z" : "Z to A"
        case .invoiceDate:
            ascending ? "Oldest first" : "Newest first"
        case .due:
            ascending ? "Most overdue first" : "Furthest due first"
        case .amount:
            ascending ? "Smallest amount first" : "Largest amount first"
        }
    }
}
