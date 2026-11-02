import Foundation

enum QuoteStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case sent
    case signed
    case void

    var title: String {
        switch self {
        case .draft: "Draft"
        case .sent: "Sent"
        case .signed: "Signed"
        case .void: "Void"
        }
    }
}
