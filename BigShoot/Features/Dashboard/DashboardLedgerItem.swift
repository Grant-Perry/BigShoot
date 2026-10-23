import Foundation
import SwiftData

struct DashboardLedgerItem: Identifiable {
    var invoice: Invoice
    /// Cash this invoice received inside the selected chart window. Nil for balance filters.
    var periodCollected: Decimal?

    var id: PersistentIdentifier { invoice.persistentModelID }
}
