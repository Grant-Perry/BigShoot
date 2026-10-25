import Foundation

struct CollectionBucket: Identifiable, Equatable {
    var start: Date
    var end: Date
    var label: String
    var collected: Decimal

    var id: Date { start }
}
