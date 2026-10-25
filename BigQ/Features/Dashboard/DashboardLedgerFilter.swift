import Foundation

/// Which invoices the dashboard list is showing.
enum DashboardLedgerFilter: Equatable, Hashable {
    case open
    case notYetDue
    case overdue
    case all
    /// Invoices that received cash in the window. `bucketStart` narrows that to one chart bar.
    case collected(CollectionWindow, Date?)
    /// Invoices dated in the window. This is the billed total, not cash received.
    case billed(CollectionWindow)
    /// Open invoices expected in one due month. Nil is the whole forecast, including amounts due later.
    case expected(Date?)

    static func cash(_ window: CollectionWindow, bucketStart: Date? = nil) -> DashboardLedgerFilter {
        .collected(window, bucketStart)
    }

    static func issued(_ window: CollectionWindow) -> DashboardLedgerFilter {
        .billed(window)
    }

    var collectionWindow: CollectionWindow? {
        guard case .collected(let window, _) = self else { return nil }
        return window
    }

    var billedWindow: CollectionWindow? {
        guard case .billed(let window) = self else { return nil }
        return window
    }

    var bucketStart: Date? {
        guard case .collected(_, let start) = self else { return nil }
        return start
    }

    var isExpected: Bool {
        if case .expected = self { return true }
        return false
    }

    var expectedMonthStart: Date? {
        guard case .expected(let start) = self else { return nil }
        return start
    }
}
