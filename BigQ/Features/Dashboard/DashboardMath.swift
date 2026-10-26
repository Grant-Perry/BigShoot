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
        range: DateInterval? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CollectionReport {
        let span = interval(for: window, range: range, now: now, calendar: calendar)
        let prior = priorInterval(for: window, range: range, now: now, calendar: calendar)
        return CollectionReport(
            total: collected(in: receipts, from: span.start, until: span.end),
            priorTotal: collected(in: receipts, from: prior.start, until: prior.end),
            buckets: buckets(in: span, window: window, receipts: receipts, calendar: calendar)
        )
    }

    static func openBook(
        in invoices: [Invoice],
        now: Date = .now,
        excluding excludedCustomers: Set<String> = []
    ) -> OpenBookSplit {
        var current = Decimal.zero
        var overdue = Decimal.zero
        for invoice in invoices where includes(invoice, excluding: excludedCustomers) {
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

    /// One row per open-invoice customer, in name order. Differently cased spellings share a row.
    static func openCustomers(in invoices: [Invoice]) -> [OpenInvoiceCustomer] {
        var balances: [String: Decimal] = [:]
        var names: [String: String] = [:]
        for invoice in invoices where invoice.holdsOpenBalance {
            let name = customerName(for: invoice)
            let key = customerKey(for: name)
            balances[key, default: 0] += max(invoice.balance, 0)
            if names[key] == nil {
                names[key] = name
            }
        }
        return balances.map { key, balance in
            OpenInvoiceCustomer(id: key, name: names[key] ?? key, balance: balance)
        }
        .sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func customerName(for invoice: Invoice) -> String {
        let trimmed = invoice.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No client" : trimmed
    }

    static func customerKey(for invoice: Invoice) -> String {
        customerKey(for: customerName(for: invoice))
    }

    static func customerKey(for name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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

    /// Sum of invoice totals dated inside the window. Void invoices are left out.
    static func invoiced(
        in invoices: [Invoice],
        window: CollectionWindow,
        range: DateInterval? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Decimal {
        let span = interval(for: window, range: range, now: now, calendar: calendar)
        return invoiced(in: invoices, from: span.start, until: span.end)
    }

    static func interval(
        for window: CollectionWindow,
        range: DateInterval? = nil,
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
        case .range:
            guard let range else { return currentMonth }
            return safeInterval(from: range.start, to: range.end)
        }
    }

    /// Inclusive calendar days, half-open so the end date counts.
    static func normalizedRange(start: Date, end: Date, calendar: Calendar = .current) -> DateInterval {
        let first = calendar.startOfDay(for: min(start, end))
        let last = calendar.startOfDay(for: max(start, end))
        let exclusiveEnd = adding(.day, value: 1, to: last, calendar: calendar)
        return safeInterval(from: first, to: exclusiveEnd)
    }

    static func priorInterval(
        for window: CollectionWindow,
        range: DateInterval? = nil,
        now: Date,
        calendar: Calendar
    ) -> DateInterval {
        let current = interval(for: window, range: range, now: now, calendar: calendar)
        switch window {
        case .year:
            let start = adding(.year, value: -1, to: current.start, calendar: calendar)
            let end = adding(.year, value: -1, to: current.end, calendar: calendar)
            return safeInterval(from: start, to: end)
        case .range:
            let days = calendar.dateComponents([.day], from: current.start, to: current.end).day ?? 0
            let start = adding(.day, value: -days, to: current.start, calendar: calendar)
            return safeInterval(from: start, to: current.start)
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

    // MARK: - Cash flow

    /// How many months the forecast chart shows, starting with the current month.
    static let cashFlowMonthCount = 6

    /// Open balances placed on the month they are due. Past-due and undated invoices land in the current month.
    static func cashFlow(
        in invoices: [Invoice],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CashFlowReport {
        let current = monthInterval(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        var starts: [Date] = []
        var cursor = current.start
        for _ in 0..<cashFlowMonthCount {
            starts.append(cursor)
            let next = monthInterval(containing: cursor, calendar: calendar).end
            if next <= cursor { break }
            cursor = next
        }
        let horizonEnd = cursor
        var totals = Array(repeating: Decimal.zero, count: starts.count)
        var pastDue = Decimal.zero
        var later = Decimal.zero

        for invoice in invoices {
            let amount = expectedAmount(invoice)
            guard amount > 0 else { continue }
            let bucket = expectedMonthStart(
                due: invoice.dueDate,
                currentMonthStart: current.start,
                today: today,
                calendar: calendar
            )
            if let index = starts.firstIndex(where: { calendar.isDate($0, inSameDayAs: bucket) }) {
                totals[index] += amount
                if let due = invoice.dueDate, due < today {
                    pastDue += amount
                }
            } else {
                later += amount
            }
        }

        let months = starts.enumerated().map { index, start in
            let crossedYear = index > 0 && !calendar.isDate(start, equalTo: starts[index - 1], toGranularity: .year)
            let end = index + 1 < starts.count ? starts[index + 1] : horizonEnd
            return CashFlowMonth(
                start: start,
                end: end,
                label: monthLabel(for: start, calendar: calendar, includeYear: crossedYear),
                expected: totals[index]
            )
        }
        return CashFlowReport(
            months: months,
            thisMonth: totals.first ?? 0,
            pastDue: pastDue,
            later: later
        )
    }

    // MARK: - Invoice ledger

    static func ledgerItems(
        _ invoices: [Invoice],
        receipts: [PaymentReceipt] = [],
        filter: DashboardLedgerFilter,
        search: String,
        range: DateInterval? = nil,
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
            let span = collectedSpan(
                window: window,
                bucketStart: bucketStart,
                range: window == .range ? range : nil,
                receipts: receipts,
                now: now,
                calendar: calendar
            )
            chosen = collectedItems(invoices: invoices, receipts: receipts, from: span.start, until: span.end)
        case .billed(let window):
            let span = interval(for: window, range: window == .range ? range : nil, now: now, calendar: calendar)
            chosen = billedItems(invoices: invoices, from: span.start, until: span.end)
        case .expected(let monthStart):
            chosen = sortByDue(
                invoices.filter { invoice in
                    belongsInForecast(invoice, monthStart: monthStart, now: now, calendar: calendar)
                }
            )
            .map { DashboardLedgerItem(invoice: $0, periodCollected: nil) }
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

    /// Orders a ledger. Invoices with no due date stay last when sorting by days.
    static func sortedLedgerItems(
        _ items: [DashboardLedgerItem],
        by sort: InvoiceLedgerSort,
        ascending: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DashboardLedgerItem] {
        items.sorted { lhs, rhs in
            let ranked = rank(lhs, rhs, by: sort, ascending: ascending, now: now, calendar: calendar)
            if ranked != .orderedSame {
                return ranked == .orderedAscending
            }
            return lhs.invoice.displayNumber.localizedStandardCompare(rhs.invoice.displayNumber) == .orderedAscending
        }
    }

    // MARK: - Private

    private static func expectedAmount(_ invoice: Invoice) -> Decimal {
        guard invoice.status != .void, invoice.balance > 0 else { return 0 }
        return invoice.balance
    }

    /// Undated and already-late invoices are expected now, so they share the current month.
    private static func expectedMonthStart(
        due: Date?,
        currentMonthStart: Date,
        today: Date,
        calendar: Calendar
    ) -> Date {
        guard let due, due >= today else { return currentMonthStart }
        let month = monthInterval(containing: due, calendar: calendar).start
        if month < currentMonthStart { return currentMonthStart }
        return month
    }

    private static func belongsInForecast(
        _ invoice: Invoice,
        monthStart: Date?,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard expectedAmount(invoice) > 0 else { return false }
        guard let monthStart else { return true }
        let current = monthInterval(containing: now, calendar: calendar)
        let bucket = expectedMonthStart(
            due: invoice.dueDate,
            currentMonthStart: current.start,
            today: calendar.startOfDay(for: now),
            calendar: calendar
        )
        return calendar.isDate(bucket, inSameDayAs: monthStart)
    }

    private static func includes(_ invoice: Invoice, excluding excludedCustomers: Set<String>) -> Bool {
        !excludedCustomers.contains(customerKey(for: invoice))
    }

    private static func collectedSpan(
        window: CollectionWindow,
        bucketStart: Date?,
        range: DateInterval?,
        receipts: [PaymentReceipt],
        now: Date,
        calendar: Calendar
    ) -> DateInterval {
        let span = interval(for: window, range: range, now: now, calendar: calendar)
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

    private static func rank(
        _ lhs: DashboardLedgerItem,
        _ rhs: DashboardLedgerItem,
        by sort: InvoiceLedgerSort,
        ascending: Bool,
        now: Date,
        calendar: Calendar
    ) -> ComparisonResult {
        switch sort {
        case .client:
            return directed(
                lhs.invoice.clientName.localizedStandardCompare(rhs.invoice.clientName),
                ascending: ascending
            )
        case .invoiceDate:
            return directed(
                compareValues(lhs.invoice.invoiceDate, rhs.invoice.invoiceDate),
                ascending: ascending
            )
        case .amount:
            return directed(
                compareValues(lhs.invoice.balance, rhs.invoice.balance),
                ascending: ascending
            )
        case .due:
            return compareDue(lhs.invoice, rhs.invoice, ascending: ascending, now: now, calendar: calendar)
        }
    }

    /// Missing due dates sort after every dated invoice, in either direction.
    private static func compareDue(
        _ lhs: Invoice,
        _ rhs: Invoice,
        ascending: Bool,
        now: Date,
        calendar: Calendar
    ) -> ComparisonResult {
        switch (daysUntilDue(lhs, now: now, calendar: calendar), daysUntilDue(rhs, now: now, calendar: calendar)) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        case let (left?, right?):
            return directed(compareValues(left, right), ascending: ascending)
        }
    }

    private static func daysUntilDue(_ invoice: Invoice, now: Date, calendar: Calendar) -> Int? {
        guard let due = invoice.dueDate else { return nil }
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: due)
        ).day
    }

    private static func compareValues<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private static func directed(_ natural: ComparisonResult, ascending: Bool) -> ComparisonResult {
        if ascending { return natural }
        switch natural {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
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
        switch window {
        case .month:
            return weekBuckets(in: interval, receipts: receipts, calendar: calendar)
        case .range:
            return rangeBuckets(in: interval, receipts: receipts, calendar: calendar)
        case .threeMonths, .sixMonths, .year:
            return monthBuckets(in: interval, receipts: receipts, calendar: calendar)
        }
    }

    /// Short custom ranges stay in weeks. Longer ones use months, then years, so labels stay readable.
    private static func rangeBuckets(
        in interval: DateInterval,
        receipts: [PaymentReceipt],
        calendar: Calendar
    ) -> [CollectionBucket] {
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        if days <= 62 {
            return weekBuckets(in: interval, receipts: receipts, calendar: calendar, limit: 16)
        }
        if days <= 1_100 {
            return monthBuckets(in: interval, receipts: receipts, calendar: calendar, limit: 40)
        }
        return yearBuckets(in: interval, receipts: receipts, calendar: calendar)
    }

    private static func weekBuckets(
        in interval: DateInterval,
        receipts: [PaymentReceipt],
        calendar: Calendar,
        limit: Int = 8
    ) -> [CollectionBucket] {
        let closing = adding(.second, value: -1, to: interval.end, calendar: calendar)
        let includeMonth = !calendar.isDate(interval.start, equalTo: closing, toGranularity: .month)
        var buckets: [CollectionBucket] = []
        var start = interval.start
        var steps = 0
        while start < interval.end, steps < limit {
            let next = adding(.day, value: 7, to: start, calendar: calendar)
            let end = min(next, interval.end)
            if end <= start { break }
            buckets.append(
                CollectionBucket(
                    start: start,
                    end: end,
                    label: daySpanLabel(from: start, until: end, calendar: calendar, includeMonth: includeMonth),
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
        calendar: Calendar,
        limit: Int = 18
    ) -> [CollectionBucket] {
        let closing = adding(.second, value: -1, to: interval.end, calendar: calendar)
        let includeYear = !calendar.isDate(interval.start, equalTo: closing, toGranularity: .year)
        var buckets: [CollectionBucket] = []
        var start = interval.start
        var steps = 0
        while start < interval.end, steps < limit {
            let month = monthInterval(containing: start, calendar: calendar)
            let end = min(month.end, interval.end)
            if end <= start { break }
            buckets.append(
                CollectionBucket(
                    start: start,
                    end: end,
                    label: monthLabel(for: start, calendar: calendar, includeYear: includeYear),
                    collected: collected(in: receipts, from: start, until: end)
                )
            )
            start = end
            steps += 1
        }
        return buckets
    }

    private static func yearBuckets(
        in interval: DateInterval,
        receipts: [PaymentReceipt],
        calendar: Calendar,
        limit: Int = 12
    ) -> [CollectionBucket] {
        var buckets: [CollectionBucket] = []
        var start = interval.start
        var steps = 0
        while start < interval.end, steps < limit {
            let year = calendar.dateInterval(of: .year, for: start) ?? DateInterval(start: start, duration: 0)
            let end = min(year.end, interval.end)
            if end <= start { break }
            buckets.append(
                CollectionBucket(
                    start: start,
                    end: end,
                    label: String(calendar.component(.year, from: start)),
                    collected: collected(in: receipts, from: start, until: end)
                )
            )
            start = end
            steps += 1
        }
        return buckets
    }

    private static func billedItems(
        invoices: [Invoice],
        from start: Date,
        until end: Date
    ) -> [DashboardLedgerItem] {
        invoices.compactMap { invoice in
            guard invoice.status != .void else { return nil }
            guard invoice.invoiceDate >= start, invoice.invoiceDate < end else { return nil }
            return DashboardLedgerItem(invoice: invoice, periodCollected: nil, showsInvoiceTotal: true)
        }
        .sorted { lhs, rhs in
            if lhs.invoice.invoiceDate != rhs.invoice.invoiceDate {
                return lhs.invoice.invoiceDate > rhs.invoice.invoiceDate
            }
            return lhs.invoice.displayNumber.localizedStandardCompare(rhs.invoice.displayNumber) == .orderedAscending
        }
    }

    private static func invoiced(in invoices: [Invoice], from start: Date, until end: Date) -> Decimal {
        invoices.reduce(.zero) { partial, invoice in
            guard invoice.status != .void else { return partial }
            guard invoice.invoiceDate >= start, invoice.invoiceDate < end else { return partial }
            return partial + invoice.total
        }
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

    private static func monthLabel(for date: Date, calendar: Calendar, includeYear: Bool = false) -> String {
        let month = calendar.component(.month, from: date)
        let symbols = calendar.shortMonthSymbols
        guard symbols.indices.contains(month - 1) else { return "\(month)" }
        let name = symbols[month - 1]
        guard includeYear else { return name }
        let year = calendar.component(.year, from: date) % 100
        return "\(name) ’\(String(format: "%02d", year))"
    }

    private static func daySpanLabel(
        from start: Date,
        until end: Date,
        calendar: Calendar,
        includeMonth: Bool = false
    ) -> String {
        let startDay = calendar.component(.day, from: start)
        let last = adding(.day, value: -1, to: end, calendar: calendar)
        let endDay = calendar.component(.day, from: last)
        let sameMonth = calendar.isDate(start, equalTo: last, toGranularity: .month)
        if !includeMonth, sameMonth {
            if startDay == endDay { return "\(startDay)" }
            return "\(startDay)–\(endDay)"
        }
        if sameMonth {
            let name = monthLabel(for: start, calendar: calendar)
            if startDay == endDay { return "\(name) \(startDay)" }
            return "\(name) \(startDay)–\(endDay)"
        }
        let opening = "\(monthLabel(for: start, calendar: calendar)) \(startDay)"
        let closing = "\(monthLabel(for: last, calendar: calendar)) \(endDay)"
        return "\(opening)–\(closing)"
    }
}
