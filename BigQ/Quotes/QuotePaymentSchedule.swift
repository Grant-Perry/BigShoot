import Foundation

struct DraftPaymentTerm: Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String = ""
    var amountMode: QuotePaymentAmountMode = .percentOfTotal
    /// Whole percent, e.g. 50.
    var percent: Decimal = 0
    var fixedAmount: Decimal = 0
    var dueMode: QuotePaymentDueMode = .signature
    var daysBeforeEvent: Int = 30
    var fixedDueDate: Date = .now
    /// Resolved dollars for the current quote total.
    var amount: Decimal = 0
}

enum QuotePaymentSchedule {
    /// Equal dollar splits. Leftover cents land on the last payment so the sum is exact.
    static func equalAmounts(total: Decimal, count: Int) -> [Decimal] {
        guard count > 0 else { return [] }
        var scaled = total * 100
        var centsDecimal = Decimal()
        NSDecimalRound(&centsDecimal, &scaled, 0, .plain)
        let cents = NSDecimalNumber(decimal: centsDecimal).intValue
        let base = cents / count
        var parts = Array(repeating: Decimal(base) / 100, count: count)
        let leftover = cents - (base * count)
        if leftover != 0 {
            parts[count - 1] += Decimal(leftover) / 100
        }
        return parts
    }

    /// Monthly due dates from a start date. Caller may edit any date afterward.
    static func monthlyDates(starting start: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        let day = calendar.startOfDay(for: start)
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: day)
        }
    }

    static func generateScheduled(
        total: Decimal,
        count: Int,
        starting start: Date
    ) -> [DraftPaymentTerm] {
        let amounts = equalAmounts(total: total, count: count)
        let dates = monthlyDates(starting: start, count: count)
        return zip(amounts, dates).enumerated().map { index, pair in
            DraftPaymentTerm(
                title: "Payment \(index + 1)",
                amountMode: .equalShare,
                dueMode: .fixedDate,
                fixedDueDate: pair.1,
                amount: pair.0
            )
        }
    }

    static func recalculate(_ terms: inout [DraftPaymentTerm], total: Decimal) {
        let equalCount = terms.filter { $0.amountMode == .equalShare }.count
        let equalParts = equalAmounts(total: total, count: max(equalCount, 0))
        var equalIndex = 0
        var running: Decimal = 0

        for i in terms.indices {
            switch terms[i].amountMode {
            case .equalShare:
                let amount = equalIndex < equalParts.count ? equalParts[equalIndex] : 0
                equalIndex += 1
                terms[i].amount = amount
                running += amount
            case .percentOfTotal:
                let amount = (total * terms[i].percent / 100).rounded(cents: true)
                terms[i].amount = amount
                running += amount
            case .fixedAmount:
                terms[i].amount = terms[i].fixedAmount.rounded(cents: true)
                running += terms[i].amount
            case .remainingBalance:
                break
            }
        }

        for i in terms.indices where terms[i].amountMode == .remainingBalance {
            let rest = max(0, total - running)
            // Only the first remaining-balance row claims the rest.
            terms[i].amount = rest
            running += rest
            break
        }
        // Extra remaining rows stay zero.
        var sawRemaining = false
        for i in terms.indices where terms[i].amountMode == .remainingBalance {
            if sawRemaining {
                terms[i].amount = 0
            } else {
                sawRemaining = true
            }
        }
    }

    static func allocated(in terms: [DraftPaymentTerm]) -> Decimal {
        terms.reduce(0) { $0 + $1.amount }
    }

    private static let moneyTolerance = Decimal(string: "0.005")!
    private static let percentTolerance = Decimal(string: "0.05")!

    /// Whole-percent intent for schedules before a quote total exists.
    static func declaredPercent(in terms: [DraftPaymentTerm]) -> Decimal {
        let sumPercent = terms
            .filter { $0.amountMode == .percentOfTotal }
            .reduce(0) { $0 + $1.percent }
        let hasRemaining = terms.contains { $0.amountMode == .remainingBalance }
        if hasRemaining {
            return sumPercent + max(0, 100 - sumPercent)
        }
        return sumPercent
    }

    /// Percent / remaining-balance rows that sum to 100% when dollars are still unknown.
    static func isStructurallyComplete(_ terms: [DraftPaymentTerm]) -> Bool {
        guard !terms.isEmpty else { return true }
        if terms.contains(where: { $0.amountMode == .equalShare || $0.amountMode == .fixedAmount }) {
            return false
        }
        return abs(declaredPercent(in: terms) - 100) < percentTolerance
    }

    static func isComplete(_ terms: [DraftPaymentTerm], total: Decimal) -> Bool {
        guard total >= 0 else { return terms.isEmpty }
        if terms.isEmpty { return total == 0 }
        if total == 0 {
            return isStructurallyComplete(terms)
        }
        return abs(allocated(in: terms) - total) < moneyTolerance
    }

    static func completenessSummary(terms: [DraftPaymentTerm], total: Decimal) -> (text: String, isComplete: Bool) {
        if terms.isEmpty {
            return ("Add payments until the schedule covers the full quote total.", false)
        }
        if isComplete(terms, total: total) {
            if total == 0 {
                return ("Schedule ready · 100% (amounts follow total)", true)
            }
            return ("Covers \(StudioMoney.string(total)) · 100%", true)
        }
        if total == 0 {
            let declared = declaredPercent(in: terms)
            let need = max(0, 100 - declared)
            return (
                "Allocated \(percentText(declared)) — need \(percentText(need)) more",
                false
            )
        }
        return (
            "Allocated \(StudioMoney.string(allocated(in: terms))) of \(StudioMoney.string(total))",
            false
        )
    }

    private static func percentText(_ value: Decimal) -> String {
        var rounded = value
        var result = Decimal()
        NSDecimalRound(&result, &rounded, 0, .plain)
        return "\(NSDecimalNumber(decimal: result).intValue)%"
    }

    static func resolveDue(
        _ term: DraftPaymentTerm,
        signatureDate: Date?,
        eventDate: Date?,
        fallback: Date = .now
    ) -> Date? {
        switch term.dueMode {
        case .signature:
            return signatureDate.map { Calendar.current.startOfDay(for: $0) }
                ?? Calendar.current.startOfDay(for: fallback)
        case .daysBeforeEvent:
            guard let eventDate else { return nil }
            return Calendar.current.date(
                byAdding: .day,
                value: -term.daysBeforeEvent,
                to: Calendar.current.startOfDay(for: eventDate)
            )
        case .fixedDate:
            return Calendar.current.startOfDay(for: term.fixedDueDate)
        }
    }

    static func summaryLine(_ term: DraftPaymentTerm) -> String {
        let amountLabel: String
        switch term.amountMode {
        case .percentOfTotal where term.amount == 0 && term.percent != 0:
            amountLabel = percentText(term.percent)
        case .remainingBalance where term.amount == 0:
            amountLabel = "Remaining balance"
        default:
            amountLabel = StudioMoney.string(term.amount)
        }
        let due: String
        switch term.dueMode {
        case .signature:
            due = "at signature"
        case .daysBeforeEvent:
            due = "\(term.daysBeforeEvent) days before event"
        case .fixedDate:
            due = StudioDay.string(term.fixedDueDate)
        }
        let title = term.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return "\(amountLabel) · \(due)" }
        return "\(title): \(amountLabel) · \(due)"
    }

    static func drafts(from job: Job) -> [DraftPaymentTerm] {
        job.sortedPaymentTerms.map { term in
            DraftPaymentTerm(
                title: term.title,
                amountMode: term.amountMode,
                percent: term.percent,
                fixedAmount: term.fixedAmount,
                dueMode: term.dueMode,
                daysBeforeEvent: term.daysBeforeEvent,
                fixedDueDate: term.fixedDueDate ?? .now,
                amount: term.amount
            )
        }
    }

    static func copySchedule(from job: Job, into draft: QuoteDraftModel) {
        guard job.paymentScheduleMode != .none, !job.paymentTerms.isEmpty else { return }
        draft.paymentScheduleMode = job.paymentScheduleMode
        draft.paymentTerms = drafts(from: job)
        draft.refreshPaymentAmounts()
    }

    /// Agreement copy for `[Terms]` — one payment per line.
    static func agreementTermsHTML(for quote: Quote) -> String {
        joinAgreementTermsLines(agreementTermsLines(for: quote))
    }

    /// Job contracts / live-fill before a quote total exists.
    static func agreementTermsHTML(for job: Job) -> String {
        agreementTermsHTML(
            mode: job.paymentScheduleMode,
            terms: drafts(from: job),
            total: 0,
            eventDate: job.eventDate
        )
    }

    /// Live-fill path for the quote editor (no persisted `Quote` yet).
    static func agreementTermsHTML(
        mode: QuotePaymentScheduleMode,
        terms: [DraftPaymentTerm],
        total: Decimal,
        eventDate: Date?
    ) -> String {
        joinAgreementTermsLines(
            agreementTermsLines(
                mode: mode,
                terms: terms,
                total: total,
                eventDate: eventDate
            )
        )
    }

    /// U+2028 keeps one paragraph so the editor can hang continuations under `Pay Details: `.
    private static func joinAgreementTermsLines(_ lines: [String]) -> String {
        lines.joined(separator: "&#8232;")
    }

    static func agreementTermsLines(for quote: Quote) -> [String] {
        let drafts = quote.sortedPaymentTerms.map { term in
            DraftPaymentTerm(
                title: term.title,
                amountMode: term.amountMode,
                percent: term.percent,
                fixedAmount: term.fixedAmount,
                dueMode: term.dueMode,
                daysBeforeEvent: term.daysBeforeEvent,
                fixedDueDate: term.fixedDueDate ?? .now,
                amount: term.amount
            )
        }
        return agreementTermsLines(
            mode: quote.paymentScheduleMode,
            terms: drafts,
            total: quote.total,
            eventDate: quote.job?.eventDate
        )
    }

    static func agreementTermsLines(
        mode: QuotePaymentScheduleMode,
        terms: [DraftPaymentTerm],
        total: Decimal,
        eventDate: Date?
    ) -> [String] {
        guard mode != .none, !terms.isEmpty else { return [] }
        var drafts = terms
        recalculate(&drafts, total: total)
        return drafts.map { agreementLine($0, eventDate: eventDate) }
    }

    /// Amount first — e.g. `50% due at signing`, `25%, 90 days prior (7/5/27)`.
    static func agreementLine(_ term: DraftPaymentTerm, eventDate: Date?) -> String {
        let amountLabel: String
        switch term.amountMode {
        case .percentOfTotal where term.amount == 0 && term.percent != 0:
            amountLabel = percentText(term.percent)
        case .remainingBalance where term.amount == 0:
            amountLabel = "Remaining balance"
        default:
            amountLabel = StudioMoney.string(term.amount)
        }
        switch term.dueMode {
        case .signature:
            return "\(amountLabel) due at signing"
        case .daysBeforeEvent:
            let prior = daysPriorPhrase(term.daysBeforeEvent)
            if let due = resolveDue(term, signatureDate: nil, eventDate: eventDate) {
                return "\(amountLabel) \(prior) (\(compactDate(due)))"
            }
            return "\(amountLabel) \(prior)"
        case .fixedDate:
            return "\(amountLabel) \(compactDate(term.fixedDueDate))"
        }
    }

    private static func daysPriorPhrase(_ days: Int) -> String {
        days == 1 ? "1 day prior" : "\(days) days prior"
    }

    /// Compact due date like `1/23/27`.
    private static func compactDate(_ date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date) % 100
        return "\(month)/\(day)/\(String(format: "%02d", year))"
    }
}

private extension Decimal {
    func rounded(cents: Bool) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, cents ? 2 : 0, .plain)
        return result
    }
}
