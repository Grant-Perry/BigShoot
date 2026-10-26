import Foundation
import SwiftData

/// One row in the audit trail. Snapshots stay after the invoice is deleted.
@Model
final class BooksEvent {
    var occurredAt: Date
    var kindRaw: String
    var invoiceKey: String
    var invoiceNumber: String
    var clientName: String
    var amount: Decimal
    var detail: String
    /// Stable id written into a backup. Empty until the first backup stamps it.
    var archiveID: String = ""

    init(
        occurredAt: Date = .now,
        kind: BooksEventKind,
        invoiceKey: String,
        invoiceNumber: String,
        clientName: String,
        amount: Decimal,
        detail: String
    ) {
        self.occurredAt = occurredAt
        self.kindRaw = kind.rawValue
        self.invoiceKey = invoiceKey
        self.invoiceNumber = invoiceNumber
        self.clientName = clientName
        self.amount = amount
        self.detail = detail
    }

    var kind: BooksEventKind {
        get { BooksEventKind(rawValue: kindRaw) ?? .edited }
        set { kindRaw = newValue.rawValue }
    }
}
