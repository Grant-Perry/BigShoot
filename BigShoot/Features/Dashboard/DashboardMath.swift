import Foundation
import SwiftData

enum DashboardMath {
    // MARK: - Balances

    static func openBalance(in invoices: [Invoice]) -> Decimal {
        invoices.reduce(Decimal.zero) { partial, invoice in
            guard invoice.status != .void, invoice.balance > 0 else { return partial }
            return partial + invoice.balance
        }
    }

    static func openCount(in invoices: [Invoice]) -> Int {
        invoices.filter(\.holdsOpenBalance).count
    }

    static func overdue(in invoices: [Invoice], now: Date = .now) -> [Invoice] {
        invoices
            .filter { $0.displayStatus == .overdue }
            .sorted { lhs, rhs in
                (lhs.dueDate ?? now) < (rhs.dueDate ?? now)
            }
    }

    static func overdueBalance(in invoices: [Invoice], now: Date = .now) -> Decimal {
        overdue(in: invoices, now: now).reduce(.zero) { partial, invoice in
            partial + max(invoice.balance, 0)
        }
    }

    // MARK: - Cash windows

    /// `total` is cash on payment receipts inside the window.
    static func collectionReport(
        receipts: [PaymentReceipt],
        window: CollectionWindow,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CollectionReport {
        let span = interval(for: window, now: now, calendar: calendar)
        let prior = priorInterval(for: window, now: now, calendar: calendar)
        return CollectionReport(
            total: collected(in: receipts, from: span.start, until: span.end),
            priorTotal: collected(in: receipts, from: prior.start, until: prior.end),
            buckets: buckets(in: span, window: window, receipts: receipts, calendar: calendar)
        )
    }

    static func openBook(in invoices: [Invoice], now: Date = .now) -> OpenBookSplit {
        var current = Decimal.zero
        var overdue = Decimal.zero
        for invoice in invoices {
            let status = InvoiceMath.displayStatus(
                stored: invoice.status,
                balance: invoice.balance,
                dueDate: invoice.dueDate,
                now: now
            )
            let balance = max(invoice.balance, 0)
            switch status {
            case .overdue:
                overdue += balance
            case .draft, .pending:
                current += balance
            case .paid, .void:
                break
            }
        }
        return OpenBookSplit(current: current, overdue: overdue)
    }

    static func collectedThisMonth(
        in receipts: [PaymentReceipt],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Decimal {
        let span = interval(for: .month, now: now, calendar: calendar)
        return collected(in: receipts, from: span.start, until: span.end)
    }

    static func collectedThisYear(
        in receipts: [PaymentReceipt],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Decimal {
        let span = interval(for: .year, now: now, calendar: calendar)
        return collected(in: receipts, from: span.start, until: span.end)
    }

    static func interval(
        for window: CollectionWindow,
        now: Date,
        calendar: Calendar
    ) -> DateInterval {
        let currentMonth = monthInterval(containing: now, calendar: calendar)
        switch window {
        case .month:
            return currentMonth
        case .threeMonths, .sixMonths:
            let start = adding(.month, value: 1 - window.trailingMonths, to: currentMonth.start, calendar: calendar)
            return safeInterval(from: start, to: currentMonth.end)
        case .year:
            let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? currentMonth.start
            return safeInterval(from: yearStart, to: currentMonth.end)
        }
    }

    static func priorInterval(
        for window: CollectionWindow,
        now: Date,
        calendar: Calendar
    ) -> DateInterval {
        let current = interval(for: window, now: now, calendar: calendar)
        switch window {
        case .year:
            let start = adding(.year, value: -1, to: current.start, calendar: calendar)
            let end = adding(.year, value: -1, to: current.end, calendar: calendar)
            return safeInterval(from: start, to: end)
        case .month, .threeMonths, .sixMonths:
            let start = adding(.month, value: -window.trailingMonths, to: current.start, calendar: calendar)
            return safeInterval(from: start, to: current.start)
        }
    }

    static func chartDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    static func percentChange(current: Decimal, prior: Decimal) -> Double? {
        guard prior > 0 else { return nil }
        return chartDouble((current - prior) / prior)
    }

    static func comparisonCaption(current: Decimal, prior: Decimal, window: CollectionWindow) -> String? {
        let phrase = window.priorPhrase
        guard prior > 0 else {
            return current > 0 ? "Nothing collected in the prior \(phrase)" : nil
        }
        if current == prior {
            return "Even with the prior \(phrase)"
        }
        guard let change = percentChange(current: current, prior: prior) else { return nil }
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        let direction = change > 0 ? "above" : "below"
        return "\(percent) \(direction) the prior \(phrase)"
    }

    // MARK: - Invoice ledger

    static func ledgerItems(
        _ invoices: [Invoice],
        receipts: [PaymentReceipt] = [],
        filter: DashboardLedgerFilter,
        search: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DashboardLedgerItem] {
        let chosen: [DashboardLedgerItem]
        switch filter {
        case .open:
            chosen = sortByDue(invoices.filter(\.holdsOpenBalance)).map { DashboardLedgerItem(invoice: $0, periodCollected: nil) }
        case .notYetDue:
            chosen = sortByDue(notYetDue(in: invoices, now: now)).map { DashboardLedgerItem(invoice: $0, periodCollected: nil) }
        case .overdue:
            chosen = overdue(in: invoices, now: now).map { DashboardLedgerItem(invoice: $0, periodCollected: nil) }
        case .all:
            chosen = sortByRecent(invoices).map { DashboardLedgerItem(invoice: $0, periodCollected: nil) }
        case .collected(let window, let bucketStart):
            let span = collectedSpan(window: window, bucketStart: bucketStart, receipts: receipts, now: now, calendar: calendar)
            chosen = collectedItems(invoices: invoices, receipts: receipts, from: span.start, until: span.end)
        }
        return chosen.filter { matches($0.invoice, search: search) }
    }

    static func notYetDue(in invoices: [Invoice], now: Date = .now) -> [Invoice] {
        invoices.filter { invoice in
            let status = InvoiceMath.displayStatus(
                stored: invoice.status,
                balance: invoice.balance,
                dueDate: invoice.dueDate,
                now: now
            )
            return switch status {
            case .draft, .pending:
                invoice.balance > 0
            case .overdue, .paid, .void:
                false
            }
        }
    }

    // MARK: - Private

    private static func collectedSpan(
        window: CollectionWindow,
        bucketStart: Date?,
        receipts: [PaymentReceipt],
        now: Date,
        calendar: Calendar
    ) -> DateInterval {
        let span = interval(for: window, now: now, calendar: calendar)
        guard let bucketStart else { return span }
        let series = buckets(in: span, window: window, receipts: receipts, calendar: calendar)
        guard let bucket = series.first(where: { $0.start == bucketStart }) else { return span }
        return safeInterval(from: bucket.start, to: bucket.end)
    }

    private static func collectedItems(
        invoices: [Invoice],
        receipts: [PaymentReceipt],
        from start: Date,
        until end: Date
    ) -> [DashboardLedgerItem] {
        var totals: [PersistentIdentifier: Decimal] = [:]
        for receipt in receipts {
            guard let invoice = receipt.invoice else { continue }
            guard receipt.paidAt >= start, receipt.paidAt < end else { continue }
            totals[invoice.persistentModelID, default: 0] += receipt.amount
        }
        return invoices.compactMap { invoice in
            guard let amount = totals[invoice.persistentModelID] else { return nil }
            return DashboardLedgerItem(invoice: invoice, periodCollected: amount)
        }
        .sorted { lhs, rhs in
            let left = lhs.periodCollected ?? 0
            let right = rhs.periodCollected ?? 0
            if left != right { return left > right }
            return lhs.invoice.displayNumber.localizedStandardCompare(rhs.invoice.displayNumber) == .orderedAscending
        }
    }

    private static func sortByDue(_ invoices: [Invoice]) -> [Invoice] {
        invoices.sorted { lhs, rhs in
            let leftDue = lhs.dueDate ?? .distantFuture
            let rightDue = rhs.dueDate ?? .distantFuture
            if leftDue != rightDue { return leftDue < rightDue }
            if lhs.balance != rhs.balance { return lhs.balance > rhs.balance }
            return lhs.displayNumber.localizedStandardCompare(rhs.displayNumber) == .orderedAscending
        }
    }

    private static func sortByRecent(_ invoices: [Invoice]) -> [Invoice] {
        invoices.sorted { lhs, rhs in
            if lhs.invoiceDate != rhs.invoiceDate { return lhs.invoiceDate > rhs.invoiceDate }
            return lhs.displayNumber.localizedStandardCompare(rhs.displayNumber) == .orderedAscending
        }
    }

    private static func matches(_ invoice: Invoice, search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if invoice.displayNumber.localizedStandardContains(query) { return true }
        if invoice.clientName.localizedStandardContains(query) { return true }
        if invoice.number.localizedStandardContains(query) { return true }
        if invoice.job?.name.localizedStandardContains(query) == true { return true }
        return false
    }

    private static func buckets(
        in interval: DateInterval,
        window: CollectionWindow,
        receipts: [PaymentReceipt],
        calendar: Calendar
    ) -> [CollectionBucket] {
        if window == .month {
            return weekBuckets(in: interval, receipts: receipts, calendar: calendar)
        }
        return monthBuckets(in: interval, receipts: receipts, calendar: calendar)
    }

    private static func weekBuckets(
        in interval: DateInterval,
        receipts: [PaymentReceipt],
        calendar: Calendar
    ) -> [CollectionBucket] {
        var buckets: [CollectionBucket] = []
        var start = interval.start
        var steps = 0
        while start < interval.end, steps < 8 {
            let next = adding(.day, value: 7, to: start, calendar: calendar)
            let end = min(next, interval.end)
            if end <= start { break }
            buckets.append(
                CollectionBucket(
                    start: start,
                    end: end,
                    label: daySpanLabel(from: start, until: end, calendar: calendar),
                    collected: collected(in: receipts, from: start, until: end)
                )
            )
            start = end
            steps += 1
        }
        return buckets
    }

    private static func monthBuckets(
        in interval: DateInterval,
        receipts: [PaymentReceipt],
        calendar: Calendar
    ) -> [CollectionBucket] {
        var buckets: [CollectionBucket] = []
        var start = interval.start
        var steps = 0
        while start < interval.end, steps < 18 {
            let month = monthInterval(containing: start, calendar: calendar)
            let end = min(month.end, interval.end)
            if end <= start { break }
            buckets.append(
                CollectionBucket(
                    start: start,
                    end: end,
                    label: monthLabel(for: start, calendar: calendar),
                    collected: collected(in: receipts, from: start, until: end)
                )
            )
            start = end
            steps += 1
        }
        return buckets
    }

    private static func collected(in receipts: [PaymentReceipt], from start: Date, until end: Date) -> Decimal {
        receipts.reduce(.zero) { partial, receipt in
            guard receipt.paidAt >= start, receipt.paidAt < end else { return partial }
            return partial + receipt.amount
        }
    }

    private static func monthInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
    }

    private static func safeInterval(from start: Date, to end: Date) -> DateInterval {
        guard start < end else { return DateInterval(start: start, duration: 0) }
        return DateInterval(start: start, end: end)
    }

    private static func adding(
        _ component: Calendar.Component,
        value: Int,
        to date: Date,
        calendar: Calendar
    ) -> Date {
        calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    private static func monthLabel(for date: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: date)
        let symbols = calendar.shortMonthSymbols
        guard symbols.indices.contains(month - 1) else { return "\(month)" }
        return symbols[month - 1]
    }

    private static func daySpanLabel(from start: Date, until end: Date, calendar: Calendar) -> String {
        let startDay = calendar.component(.day, from: start)
        let last = adding(.day, value: -1, to: end, calendar: calendar)
        let endDay = calendar.component(.day, from: last)
        if startDay == endDay { return "\(startDay)" }
        return "\(startDay)–\(endDay)"
    }
}
