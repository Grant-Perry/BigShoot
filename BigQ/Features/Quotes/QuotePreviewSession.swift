import Foundation
import SwiftData

/// An in-memory quote the PDF preview can draw. It is not the book of record.
@MainActor
final class QuotePreviewSession: Identifiable {
    let id = UUID()
    let container: ModelContainer
    let context: ModelContext
    let quote: Quote

    init(container: ModelContainer, context: ModelContext, quote: Quote) {
        self.container = container
        self.context = context
        self.quote = quote
    }
}
