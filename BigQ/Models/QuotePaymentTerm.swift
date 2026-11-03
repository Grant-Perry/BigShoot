import Foundation
import SwiftData

enum QuotePaymentScheduleMode: String, Codable, CaseIterable, Sendable {
    case none
    case scheduled
    case custom

    var title: String {
        switch self {
        case .none: "No schedule"
        case .scheduled: "Scheduled payments"
        case .custom: "Custom payments"
        }
    }
}

enum QuotePaymentAmountMode: String, Codable, CaseIterable, Sendable {
    case equalShare
    case percentOfTotal
    case remainingBalance
    case fixedAmount

    var title: String {
        switch self {
        case .equalShare: "Equal share"
        case .percentOfTotal: "Percentage of total"
        case .remainingBalance: "Remaining balance"
        case .fixedAmount: "Specific amount"
        }
    }
}

enum QuotePaymentDueMode: String, Codable, CaseIterable, Sendable {
    case signature
    case daysBeforeEvent
    case fixedDate

    var title: String {
        switch self {
        case .signature: "At signature"
        case .daysBeforeEvent: "Days before event"
        case .fixedDate: "Fixed date"
        }
    }
}

@Model
final class QuotePaymentTerm {
    var title: String
    var position: Int
    var amountModeRaw: String
    /// Whole percent, e.g. 50 for 50%.
    var percent: Decimal
    var fixedAmount: Decimal
    var dueModeRaw: String
    var daysBeforeEvent: Int
    var fixedDueDate: Date?
    /// Dollar amount last resolved from the quote total.
    var amount: Decimal

    var quote: Quote?

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
