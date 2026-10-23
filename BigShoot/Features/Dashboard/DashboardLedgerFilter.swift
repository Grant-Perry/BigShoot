import Foundation

/// Which invoices the dashboard list is showing.
enum DashboardLedgerFilter: Equatable, Hashable {
    case open
    case notYetDue
    case overdue
    case all
    /// Invoices that received cash in the window. `bucketStart` narrows that to one chart bar.
    case collected(CollectionWindow, Date?)

    static func cash(_ window: CollectionWindow, bucketStart: Date? = nil) -> DashboardLedgerFilter {
        .collected(window, bucketStart)
    }

    var collectionWindow: CollectionWindow? {
        guard case .collected(let window, _) = self else { return nil }
        return window
    }

    var bucketStart: Date? {
        guard case .collected(_, let start) = self else { return nil }
        return start
    }
}
