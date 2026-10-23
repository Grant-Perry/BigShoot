import Foundation

struct CollectionReport: Equatable {
    var total: Decimal
    var priorTotal: Decimal
    var buckets: [CollectionBucket]

    static let empty = CollectionReport(total: 0, priorTotal: 0, buckets: [])
}
