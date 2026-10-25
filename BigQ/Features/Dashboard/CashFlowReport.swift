import Foundation

struct CashFlowReport: Equatable {
    var months: [CashFlowMonth]
    /// Open balance landing in the current month, including anything already past due.
    var thisMonth: Decimal
    /// Part of `thisMonth` whose due date is already before today.
    var pastDue: Decimal
    /// Open balance due after the last month on the chart.
    var later: Decimal

    var horizonTotal: Decimal {
        months.reduce(.zero) { partial, month in
            partial + month.expected
        }
    }

    static let empty = CashFlowReport(months: [], thisMonth: 0, pastDue: 0, later: 0)
}
