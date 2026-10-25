import Foundation
import SwiftData

/// A named tax rate the studio can apply again. Invoices copy the rate when they use it.
@Model
final class TaxSchedule {
    #Unique<TaxSchedule>([\.name])

    var name: String
    /// Fraction, such as 0.066 for 6.6%.
    var rate: Decimal

    init(name: String, rate: Decimal) {
        self.name = name
        self.rate = rate
    }
}
