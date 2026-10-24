import SwiftData
import SwiftUI

struct DashboardLedgerRow: View {
    var invoice: Invoice
    var periodCollected: Decimal?
    var onSelect: () -> Void
    var onPay: () -> Void
    var onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(amountColor)
                        .frame(width: 3)
                        .padding(.vertical, 4)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(invoice.clientName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(StudioMoney.string(shownAmount))
                            .font(StudioDesign.metric(16))
                            .monospacedDigit()
                            .foregroundStyle(amountColor)
                        if periodCollected != nil {
                            Text("received")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if invoice.balance > 0 {
                                Text("\(StudioMoney.string(invoice.balance)) still open")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else if showsOfTotal {
                            Text("of \(StudioMoney.string(invoice.total))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        StatusBadge(status: invoice.displayStatus)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(invoice.canEditLines ? "Edits this invoice" : "Opens this invoice")

            if invoice.canRecordPayment {
                Button("Record Payment", systemImage: "dollarsign.circle", action: onPay)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Record payment")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: StudioDesign.Radius.row, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : .clear)
        )
        .onHover { hovering = $0 }
        .contextMenu {
            if invoice.canEditLines {
                Button("Edit", systemImage: "pencil", action: onSelect)
            }
            if invoice.canRecordPayment {
                Button("Record Payment", systemImage: "dollarsign.circle", action: onPay)
            }
            Button("Open in Invoices", systemImage: "doc.text", action: onOpen)
        }
    }

    private var shownAmount: Decimal {
        if let periodCollected { return periodCollected }
        if invoice.balance > 0 { return invoice.balance }
        if invoice.amountPaid > 0 { return invoice.amountPaid }
        return invoice.total
    }

    private var showsOfTotal: Bool {
        invoice.amountPaid > 0 && invoice.balance > 0 && invoice.total > 0
    }

    private var detail: String {
        let number = invoice.displayNumber
        switch invoice.displayStatus {
        case .paid, .void:
            return "\(number) · \(StudioDay.string(invoice.invoiceDate))"
        case .draft, .pending, .overdue:
            if let due = invoice.dueSummary {
                return "\(number) · \(due)"
            }
            return "\(number) · \(StudioDay.string(invoice.invoiceDate))"
        }
    }

    private var amountColor: Color {
        if periodCollected != nil { return StudioDesign.paid }
        return switch invoice.displayStatus {
        case .overdue: StudioDesign.rose
        case .paid: StudioDesign.paid
        case .void, .draft: .secondary
        case .pending: .primary
        }
    }
}
