import Foundation

enum BooksEventKind: String, Codable, CaseIterable, Sendable {
    case created
    case edited
    case markedSent
    case submitted
    case paymentApplied
    case paymentRemoved
    case deleted

    var title: String {
        switch self {
        case .created: "Created"
        case .edited: "Edited"
        case .markedSent: "Marked sent"
        case .submitted: "Submitted"
        case .paymentApplied: "Payment"
        case .paymentRemoved: "Payment removed"
        case .deleted: "Deleted"
        }
    }
}
