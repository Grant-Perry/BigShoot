import SwiftUI

struct InvoiceEditorActiveKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var invoiceEditorActive: Bool? {
        get { self[InvoiceEditorActiveKey.self] }
        set { self[InvoiceEditorActiveKey.self] = newValue }
    }
}

/// ⌘N starts an invoice from the books. Inside the editor it opens the catalog instead.
struct NewInvoiceCommand: View {
    @FocusedValue(\.invoiceEditorActive) private var invoiceEditorActive

    var body: some View {
        if invoiceEditorActive == true {
            Button("Add from Catalog") {
                NotificationCenter.default.post(name: .bigQAddCatalogItem, object: nil)
            }
            .keyboardShortcut("n")
        } else {
            Button("New Invoice") {
                NotificationCenter.default.post(name: .bigShootNewInvoice, object: nil)
            }
            .keyboardShortcut("n")
        }
    }
}
