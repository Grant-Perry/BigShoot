import Foundation

/// How far back the collected chart looks.
///
/// Month, 3 months, and 6 months include the current month and step backward by calendar month.
/// Year is the calendar year through the current month, the same span as the year total.
enum CollectionWindow: String, CaseIterable, Identifiable, Hashable, Sendable {
    case month
    case threeMonths
    case sixMonths
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "Month"
        case .threeMonths: "3 mo"
        case .sixMonths: "6 mo"
        case .year: "Year"
        }
    }

    var spokenTitle: String {
        switch self {
        case .month: "This month"
        case .threeMonths: "Last 3 months"
        case .sixMonths: "Last 6 months"
        case .year: "This year"
        }
    }

    var cashCaption: String {
        switch self {
        case .month: "Cash received this month"
        case .threeMonths: "Cash received in the last 3 months"
        case .sixMonths: "Cash received in the last 6 months"
        case .year: "Cash received this year"
        }
    }

    var billedCaption: String {
        switch self {
        case .month: "Invoices dated this month"
        case .threeMonths: "Invoices dated in the last 3 months"
        case .sixMonths: "Invoices dated in the last 6 months"
        case .year: "Invoices dated this year"
        }
    }

    var priorPhrase: String {
        switch self {
        case .month: "month"
        case .threeMonths: "3 months"
        case .sixMonths: "6 months"
        case .year: "year"
        }
    }

    /// Trailing length for every window except year, which is calendar year-to-date.
    var trailingMonths: Int {
        switch self {
        case .month: 1
        case .threeMonths: 3
        case .sixMonths: 6
        case .year: 12
        }
    }
}
