import SwiftUI

struct InvoiceContextMenu: View {
    var invoice: Invoice
    var onRecordPayment: () -> Void
    var onEdit: () -> Void
    var onPreview: () -> Void
    var onRemind: () -> Void
    var onMarkSent: () -> Void
    var onDelete: () -> Void

    var body: some View {
        if invoice.canRecordPayment {
            Button("Record Payment", systemImage: "dollarsign.circle", action: onRecordPayment)
        }
        if invoice.status == .draft {
            Button("Mark Sent", systemImage: "paperplane", action: onMarkSent)
        }
        if invoice.canEditLines {
            Button("Edit", systemImage: "pencil", action: onEdit)
        }
        Button("Preview PDF", systemImage: "doc.richtext", action: onPreview)
        Button("Remind", systemImage: "envelope", action: onRemind)
        Divider()
        Button("Delete Invoice", systemImage: "trash", role: .destructive, action: onDelete)
    }
}
