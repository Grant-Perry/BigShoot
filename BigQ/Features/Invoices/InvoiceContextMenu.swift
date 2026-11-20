import SwiftUI

struct InvoiceContextMenu: View {
    var invoice: Invoice
    var onRecordPayment: () -> Void
    var onEdit: () -> Void
    var onPreview: () -> Void
    var onSend: () -> Void
    var onMarkSent: () -> Void
    var onDelete: () -> Void

    var body: some View {
        if invoice.canRecordPayment {
            Button("Record Payment", systemImage: "dollarsign.circle", action: onRecordPayment)
                .help("Record a payment")
        }
        if invoice.status == .draft {
            Button("Mark Sent", systemImage: "paperplane", action: onMarkSent)
                .help("Mark this invoice sent")
        }
        if invoice.canEditLines {
            Button("Edit", systemImage: "pencil", action: onEdit)
                .help("Edit this invoice")
        }
        Button("Preview PDF", systemImage: "doc.richtext", action: onPreview)
            .help("Preview the invoice PDF")
        Button("Send Invoice", systemImage: "envelope", action: onSend)
            .help("Email this invoice")
        Divider()
        Button("Delete Invoice", systemImage: "trash", role: .destructive, action: onDelete)
            .help("Delete this invoice")
    }
}
