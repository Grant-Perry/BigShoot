import Foundation

enum BooksEventKind: String, Codable, CaseIterable, Sendable {
    case created
    case edited
    case markedSent
    case submitted
    case paymentApplied
    case deleted

    var title: String {
        switch self {
        case .created: "Created"
        case .edited: "Edited"
        case .markedSent: "Marked sent"
        case .submitted: "Submitted"
        case .paymentApplied: "Payment"
        case .deleted: "Deleted"
        }
    }
}
