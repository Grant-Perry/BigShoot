import Foundation

/// Money still on open invoices, split into not-yet-due and overdue.
struct OpenBookSplit: Equatable {
    var current: Decimal
    var overdue: Decimal

    var total: Decimal { current + overdue }

    static let empty = OpenBookSplit(current: 0, overdue: 0)

    func amount(for kind: Kind) -> Decimal {
        switch kind {
        case .current: current
        case .overdue: overdue
        }
    }

    var populatedKinds: [Kind] {
        Kind.allCases.filter { amount(for: $0) > 0 }
    }

    enum Kind: String, CaseIterable, Identifiable, Equatable {
        case current
        case overdue

        var id: String { rawValue }

        var title: String {
            switch self {
            case .current: "Not yet due"
            case .overdue: "Overdue"
            }
        }

        var symbol: String {
            switch self {
            case .current: "circle"
            case .overdue: "exclamationmark.circle.fill"
            }
        }
    }
}
