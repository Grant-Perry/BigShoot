import Foundation
import SwiftData

@Model
final class JobPaymentTerm {
    var title: String
    var position: Int
    var amountModeRaw: String
    /// Whole percent, e.g. 50 for 50%.
    var percent: Decimal
    var fixedAmount: Decimal
    var dueModeRaw: String
    var daysBeforeEvent: Int
    var fixedDueDate: Date?
    /// Dollar amount last resolved from a quote total (zero on the job template).
    var amount: Decimal

    var job: Job?

    init(
        title: String = "",
        position: Int = 0,
        amountMode: QuotePaymentAmountMode = .percentOfTotal,
        percent: Decimal = 0,
        fixedAmount: Decimal = 0,
        dueMode: QuotePaymentDueMode = .signature,
        daysBeforeEvent: Int = 0,
        fixedDueDate: Date? = nil,
        amount: Decimal = 0
    ) {
        self.title = title
        self.position = position
        self.amountModeRaw = amountMode.rawValue
        self.percent = percent
        self.fixedAmount = fixedAmount
        self.dueModeRaw = dueMode.rawValue
        self.daysBeforeEvent = daysBeforeEvent
        self.fixedDueDate = fixedDueDate
        self.amount = amount
    }

    var amountMode: QuotePaymentAmountMode {
        get { QuotePaymentAmountMode(rawValue: amountModeRaw) ?? .percentOfTotal }
        set { amountModeRaw = newValue.rawValue }
    }

    var dueMode: QuotePaymentDueMode {
        get { QuotePaymentDueMode(rawValue: dueModeRaw) ?? .signature }
        set { dueModeRaw = newValue.rawValue }
    }
}
