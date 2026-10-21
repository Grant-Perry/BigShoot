import Foundation
import SwiftData

@Model
final class InvoiceLine {
    var shootqID: String?
    var name: String
    var detail: String
    var quantity: Decimal
    var unitPrice: Decimal
    var position: Int
    var packageName: String

    var invoice: Invoice?
    var catalogItem: CatalogItem?

    init(
        shootqID: String? = nil,
        name: String = "",
        detail: String = "",
        quantity: Decimal = 1,
        unitPrice: Decimal = 0,
        position: Int = 0,
        packageName: String = ""
    ) {
        self.shootqID = shootqID
        self.name = name
        self.detail = detail
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.position = position
        self.packageName = packageName
    }

    var lineTotal: Decimal {
        quantity * unitPrice
    }
}
