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
