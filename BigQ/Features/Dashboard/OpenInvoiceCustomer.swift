import Foundation

/// One customer who still has money on an open invoice.
struct OpenInvoiceCustomer: Identifiable, Equatable {
    /// Case-folded customer name. Same spelling is one customer.
    var id: String
    var name: String
    var balance: Decimal
}
