import Foundation

/// How far back the collected chart looks.
///
/// Month, 3 months, and 6 months include the current month and step backward by calendar month.
/// Year is the calendar year through the current month, the same span as the year total.
/// Range is the inclusive start and end the user picks.
enum CollectionWindow: String, CaseIterable, Identifiable, Hashable, Sendable {
    case month
    case threeMonths
    case sixMonths
    case year
    case range

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "Month"
        case .threeMonths: "3 mo"
        case .sixMonths: "6 mo"
        case .year: "Year"
        case .range: "Range"
        }
    }

    var spokenTitle: String {
        switch self {
        case .month: "This month"
        case .threeMonths: "Last 3 months"
        case .sixMonths: "Last 6 months"
        case .year: "This year"
        case .range: "Custom range"
        }
    }

    var cashCaption: String {
        switch self {
        case .month: "Cash received this month"
        case .threeMonths: "Cash received in the last 3 months"
        case .sixMonths: "Cash received in the last 6 months"
        case .year: "Cash received this year"
        case .range: "Cash received in this range"
        }
    }

    func cashCaption(from start: Date, through end: Date, calendar: Calendar = .current) -> String {
        guard self == .range else { return cashCaption }
        return "Cash received \(Self.phrase(from: start, to: end, calendar: calendar))"
    }

    func spokenTitle(covering interval: DateInterval?, calendar: Calendar = .current) -> String {
        guard self == .range, let interval else { return spokenTitle }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        return Self.phrase(from: interval.start, to: lastDay, calendar: calendar)
    }

    var billedCaption: String {
        switch self {
        case .month: "Invoices dated this month"
        case .threeMonths: "Invoices dated in the last 3 months"
        case .sixMonths: "Invoices dated in the last 6 months"
        case .year: "Invoices dated this year"
        case .range: "Invoices dated in this range"
        }
    }

    func billedCaption(from start: Date, through end: Date, calendar: Calendar = .current) -> String {
        guard self == .range else { return billedCaption }
        return "Invoices dated \(Self.phrase(from: start, to: end, calendar: calendar))"
    }

    var priorPhrase: String {
        switch self {
        case .month: "month"
        case .threeMonths: "3 months"
        case .sixMonths: "6 months"
        case .year: "year"
        case .range: "period"
        }
    }

    /// Trailing length for the month presets. Year is calendar year-to-date. Range uses the picked dates.
    var trailingMonths: Int {
        switch self {
        case .month: 1
        case .threeMonths: 3
        case .sixMonths: 6
        case .year: 12
        case .range: 0
        }
    }

    static func phrase(from start: Date, to end: Date, calendar: Calendar = .current) -> String {
        let first = min(start, end)
        let last = max(start, end)
        let locale = calendar.locale ?? .autoupdatingCurrent
        let sameDay = calendar.isDate(first, equalTo: last, toGranularity: .day)
        let sameYear = calendar.isDate(first, equalTo: last, toGranularity: .year)
        if sameDay {
            return first.formatted(dateStyle(calendar: calendar, locale: locale, includeYear: true))
        }
        let opening = first.formatted(dateStyle(calendar: calendar, locale: locale, includeYear: !sameYear))
        let closing = last.formatted(dateStyle(calendar: calendar, locale: locale, includeYear: true))
        return "\(opening) – \(closing)"
    }

    private static func dateStyle(calendar: Calendar, locale: Locale, includeYear: Bool) -> Date.FormatStyle {
        var style = Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated).day()
        if includeYear {
            style = style.year()
        }
        return style
    }
}
