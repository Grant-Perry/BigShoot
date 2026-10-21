import Foundation
import SwiftData

@Model
final class CatalogItem {
    #Unique<CatalogItem>([\.name])

    var name: String
    var defaultPrice: Decimal
    var detail: String
    var timesUsed: Int

    @Relationship(deleteRule: .nullify, inverse: \InvoiceLine.catalogItem)
    var lines: [InvoiceLine]

    init(
        name: String,
        defaultPrice: Decimal = 0,
        detail: String = "",
        timesUsed: Int = 0
    ) {
        self.name = name
        self.defaultPrice = defaultPrice
        self.detail = detail
        self.timesUsed = timesUsed
        self.lines = []
    }
}
