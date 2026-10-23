import SwiftUI

struct InvoiceListRow: View {
    var invoice: Invoice

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(invoice.displayNumber)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(StudioMoney.string(invoice.balance))
                    .font(StudioDesign.metric(14))
                    .monospacedDigit()
            }
            Text(invoice.clientName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let job = invoice.job {
                Text(job.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(StudioDay.string(invoice.invoiceDate))
                    if let due = invoice.dueDate {
                        Text("·")
                        Text("Due \(StudioDay.string(due))")
                        if showsCountdown {
                            Text("·")
                            Text(InvoiceMath.dueCountdown(until: due))
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                if invoice.displayStatus == .overdue {
                    StatusBadge(status: .overdue, title: "OVERDUE")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var showsCountdown: Bool {
        invoice.displayStatus != .paid && invoice.displayStatus != .void
    }
}
