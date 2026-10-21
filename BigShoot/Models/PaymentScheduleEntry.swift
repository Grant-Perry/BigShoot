import Foundation
import SwiftData

@Model
final class PaymentScheduleEntry {
    #Unique<PaymentScheduleEntry>([\.shootqID])

    var shootqID: String?
    var due: Date?
    var amount: Decimal
    var amountPaid: Decimal
    var balance: Decimal
    var status: String

    var invoice: Invoice?

    init(
        shootqID: String? = nil,
        due: Date? = nil,
        amount: Decimal = 0,
        amountPaid: Decimal = 0,
        balance: Decimal = 0,
        status: String = ""
    ) {
        self.shootqID = shootqID
        self.due = due
        self.amount = amount
        self.amountPaid = amountPaid
        self.balance = balance
        self.status = status
    }
}
