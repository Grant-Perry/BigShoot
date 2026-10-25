import Foundation

struct CashFlowMonth: Identifiable, Equatable {
    var start: Date
    var end: Date
    var label: String
    var expected: Decimal

    var id: Date { start }
}
