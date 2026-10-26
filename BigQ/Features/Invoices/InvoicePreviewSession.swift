import Foundation
import SwiftData

/// An in-memory invoice the PDF preview can draw. It is not the book of record.
@MainActor
final class InvoicePreviewSession: Identifiable {
    let id = UUID()
    let container: ModelContainer
    let context: ModelContext
    let invoice: Invoice

    init(container: ModelContainer, context: ModelContext, invoice: Invoice) {
        self.container = container
        self.context = context
        self.invoice = invoice
    }
}
