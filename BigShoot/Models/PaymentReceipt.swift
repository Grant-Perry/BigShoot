import Foundation
import SwiftData

@Model
final class PaymentReceipt {
    #Unique<PaymentReceipt>([\.shootqID])

    var shootqID: String?
    var paidAt: Date
    var amount: Decimal
    var methodRaw: String

    var invoice: Invoice?

    init(
        shootqID: String? = nil,
        paidAt: Date = .now,
        amount: Decimal = 0,
        method: PaymentMethod = .manual
    ) {
        self.shootqID = shootqID
        self.paidAt = paidAt
        self.amount = amount
        self.methodRaw = method.rawValue
    }

    var method: PaymentMethod {
        get { PaymentMethod(rawValue: methodRaw) ?? .other }
        set { methodRaw = newValue.rawValue }
    }
}
