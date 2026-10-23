import SwiftData
import SwiftUI

struct InvoiceDetailView: View {
    var invoice: Invoice
    var onRecordPayment: () -> Void
    var onPreview: () -> Void
    var onRemind: () -> Void
    var onEdit: () -> Void
    var onMarkSent: () -> Void
    var onDelete: () -> Void

    @State private var numberHeight: CGFloat = 48
    @Query(sort: \BooksEvent.occurredAt, order: .reverse) private var booksEvents: [BooksEvent]

    private var trail: [BooksEvent] {
        BooksTrail.events(for: invoice, in: booksEvents)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                header
                billTo
                lines
                if !invoice.schedule.isEmpty { schedule }
                if !invoice.receipts.isEmpty { receipts }
                if !trail.isEmpty { auditTrail }
                if !invoice.note.isEmpty {
                    Text(invoice.note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(StudioDesign.Spacing.card)
                        .paperCard()
                }
            }
            .padding(StudioDesign.Spacing.workspace)
            .frame(maxWidth: 760, alignment: .leading)
            .textSelection(.enabled)
        }
        .contextMenu {
            InvoiceContextMenu(
                invoice: invoice,
                onRecordPayment: onRecordPayment,
                onEdit: onEdit,
                onPreview: onPreview,
                onRemind: onRemind,
                onMarkSent: onMarkSent,
                onDelete: onDelete
            )
        }
        .toolbar {
            if invoice.status == .draft {
                ToolbarItem {
                    Button("Mark Sent", action: onMarkSent)
                }
            }
            if invoice.canEditLines {
                ToolbarItem { Button("Edit", systemImage: "pencil", action: onEdit) }
            }
            ToolbarItem { Button("Preview PDF", systemImage: "doc.richtext", action: onPreview) }
            ToolbarItem { Button("Remind", systemImage: "envelope", action: onRemind) }
            ToolbarItem {
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
            if invoice.canRecordPayment {
                ToolbarItem(placement: .primaryAction) {
                    Button("Record Payment", systemImage: "dollarsign.circle", action: onRecordPayment)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 3) {
                    SidewaysInvoiceMark(maxHeight: numberHeight)
                    Text(invoice.displayNumber)
                        .font(StudioDesign.displayHero)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            guard height > 1, height != numberHeight else { return }
                            numberHeight = height
                        }
                }
                if let job = invoice.job {
                    Text(job.displayName)
                        .font(.title3)
                        .lineLimit(2)
                }
                Text(invoice.clientName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    if invoice.canEditLines {
                        Button("Edit", systemImage: "pencil", action: onEdit)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    StatusBadge(status: invoice.displayStatus)
                }
                Text(StudioMoney.string(invoice.balance))
                    .font(StudioDesign.metric(28))
                    .monospacedDigit()
                Text("Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let due = invoice.dueSummary {
                    Text("Due \(due)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var billTo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bill to")
                .font(.headline)
            Text(invoice.clientName)
            if let email = invoice.contact?.email, !email.isEmpty {
                Text(email).foregroundStyle(.secondary)
            }
            if let job = invoice.job {
                Text(job.displayName).foregroundStyle(.secondary)
            }
            HStack {
                labeled("Invoice", StudioDay.string(invoice.invoiceDate))
                labeled("Due", invoice.dueSummary ?? StudioDay.string(invoice.dueDate))
                if let paid = invoice.paidDate {
                    labeled("Paid", StudioDay.string(paid))
                }
            }
        }
        .padding(StudioDesign.Spacing.card)
        .paperCard()
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lines")
                .font(.headline)
            if invoice.lines.isEmpty {
                Text("ShootQ didn’t keep rows for this invoice. The total is still here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(invoice.sortedLines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.name)
                            Spacer()
                            Text(StudioMoney.string(line.lineTotal))
                                .monospacedDigit()
                        }
                        Text("\(plain(line.quantity)) × \(StudioMoney.string(line.unitPrice))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !line.detail.isEmpty {
                            Text(line.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Divider()
            totalRow("Tax", invoice.tax)
            totalRow("Total", invoice.total)
            totalRow("Paid", invoice.amountPaid)
            totalRow("Balance", invoice.balance, emphasis: true)
        }
        .padding(StudioDesign.Spacing.card)
        .paperCard()
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.headline)
            ForEach(invoice.schedule.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }) { entry in
                HStack {
                    Text(StudioDay.string(entry.due))
                    Text(entry.status).foregroundStyle(.secondary)
                    Spacer()
                    Text(StudioMoney.string(entry.balance))
                        .monospacedDigit()
                }
            }
        }
        .padding(StudioDesign.Spacing.card)
        .paperCard()
    }

    private var auditTrail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audit trail")
                .font(.headline)
            ForEach(trail) { event in
                BooksEventRow(event: event)
            }
        }
        .padding(StudioDesign.Spacing.card)
        .paperCard()
    }

    private var receipts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payments")
                .font(.headline)
            ForEach(invoice.receipts.sorted { $0.paidAt > $1.paidAt }) { receipt in
                HStack {
                    Text(StudioDay.string(receipt.paidAt))
                    Text(receipt.method.title).foregroundStyle(.secondary)
                    Spacer()
                    Text(StudioMoney.string(receipt.amount))
                        .monospacedDigit()
                }
            }
        }
        .padding(StudioDesign.Spacing.card)
        .paperCard()
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func totalRow(_ title: String, _ amount: Decimal, emphasis: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(emphasis ? .primary : .secondary)
            Spacer()
            Text(StudioMoney.string(amount))
                .font(emphasis ? StudioDesign.metric(18) : .body)
                .monospacedDigit()
        }
    }

    private func plain(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

// MARK: - Spine

/// “INVOICE”, turned −90°, kept inside the invoice number’s line height.
private struct SidewaysInvoiceMark: View {
    var maxHeight: CGFloat

    var body: some View {
        ViewThatFits(in: .vertical) {
            mark(16)
            mark(15)
            mark(14)
            mark(13)
            mark(12)
            mark(11)
            mark(10)
        }
        .frame(height: maxHeight)
        .accessibilityHidden(true)
    }

    private func mark(_ size: CGFloat) -> some View {
        SidewaysLayout {
            Text("INVOICE")
                .font(.system(size: size, weight: .heavy).width(.compressed))
                .foregroundStyle(.black)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Reports the child’s size with the axes swapped. The child draws its own −90° rotation.
private struct SidewaysLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(.unspecified)
        return CGSize(width: size.height, height: size.width)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let size = child.sizeThatFits(.unspecified)
        child.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: size.width, height: size.height)
        )
    }
}
