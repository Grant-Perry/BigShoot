import Foundation
import SwiftData

@Model
final class CatalogItem {
    #Unique<CatalogItem>([\.name])

    var name: String
    var defaultPrice: Decimal
    var detail: String
    /// Default for the next invoice line copied from this item. Nil on rows written before tax schedules, which means not taxable.
    var taxable: Bool?
    var timesUsed: Int

    @Relationship(deleteRule: .nullify, inverse: \InvoiceLine.catalogItem)
    var lines: [InvoiceLine]

    init(
        name: String,
        defaultPrice: Decimal = 0,
        detail: String = "",
        taxable: Bool = false,
        timesUsed: Int = 0
    ) {
        self.name = name
        self.defaultPrice = defaultPrice
        self.detail = detail
        self.taxable = taxable
        self.timesUsed = timesUsed
        self.lines = []
    }
}
