import Foundation
import SwiftData

@Model
final class QuoteLine {
    var name: String
    var detail: String
    var quantity: Decimal
    var unitPrice: Decimal
    var position: Int
    var taxable: Bool?

    var quote: Quote?
    var catalogItem: CatalogItem?

    init(
        name: String = "",
        detail: String = "",
        quantity: Decimal = 1,
        unitPrice: Decimal = 0,
        position: Int = 0,
        taxable: Bool = false
    ) {
        self.name = name
        self.detail = detail
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.position = position
        self.taxable = taxable
    }

    var lineTotal: Decimal {
        quantity * unitPrice
    }
}
