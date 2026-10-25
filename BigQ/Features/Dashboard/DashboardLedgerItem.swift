import Foundation
import SwiftData

struct DashboardLedgerItem: Identifiable {
    var invoice: Invoice
    /// Cash this invoice received inside the selected chart window. Nil for balance filters.
    var periodCollected: Decimal?
    /// The row amount is the invoice total, for a billed-period list.
    var showsInvoiceTotal: Bool = false

    var id: PersistentIdentifier { invoice.persistentModelID }
}
