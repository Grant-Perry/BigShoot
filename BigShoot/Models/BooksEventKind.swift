import Foundation

enum BooksEventKind: String, Codable, CaseIterable, Sendable {
    case created
    case edited
    case markedSent
    case paymentApplied
    case deleted

    var title: String {
        switch self {
        case .created: "Created"
        case .edited: "Edited"
        case .markedSent: "Marked sent"
        case .paymentApplied: "Payment"
        case .deleted: "Deleted"
        }
    }
}
