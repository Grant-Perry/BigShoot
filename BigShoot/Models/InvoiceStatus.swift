import Foundation

enum InvoiceStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case pending
    case overdue
    case paid
    case void

    var title: String {
        switch self {
        case .draft: "Draft"
        case .pending: "Pending"
        case .overdue: "Overdue"
        case .paid: "Paid"
        case .void: "Void"
        }
    }
}

enum PaymentMethod: String, Codable, CaseIterable, Sendable {
    case manual
    case check
    case card
    case other

    nonisolated var title: String {
        switch self {
        case .manual: "Manual"
        case .check: "Check"
        case .card: "Card"
        case .other: "Other"
        }
    }

    /// Built-in raw values stay titled. Anything else is a custom type stored as typed.
    nonisolated static func displayTitle(for stored: String) -> String {
        PaymentMethod(rawValue: stored)?.title ?? stored
    }
}
