import SwiftData
import SwiftUI

struct DashboardInvoiceLedger: View {
    var invoices: [Invoice]
    var receipts: [PaymentReceipt]
    var buckets: [CollectionBucket]
    @Binding var filter: DashboardLedgerFilter
    var onOpenInvoice: (PersistentIdentifier) -> Void
    var onShowInvoices: () -> Void
    var onNewInvoice: () -> Void

    @State private var search = ""
    @State private var editingInvoice: Invoice?
    @State private var paymentInvoice: Invoice?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            scopePicker
            StudioColumnSearch(
                text: $search,
                prompt: "Number, client, or job",
                findLabel: "Find Invoice",
                insetsHorizontally: false
            )
            list
                .frame(maxWidth: .infinity, minHeight: 420, maxHeight: 560)
        }
        .padding(StudioDesign.Spacing.card)
        .studioCard()
        .sheet(item: $editingInvoice) { invoice in
            NewInvoiceSheet(existing: invoice, onOpenInvoice: onOpenInvoice)
        }
        .sheet(item: $paymentInvoice) { invoice in
            RecordPaymentSheet(invoice: invoice)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Invoices")
                    .font(.title3)
                Text(countCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Invoice Desk", systemImage: "doc.text", action: onShowInvoices)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("New Invoice", systemImage: "plus", action: onNewInvoice)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var scopePicker: some View {
        Picker("Which invoices", selection: scopeBinding) {
            Text("Open").tag(Optional(InvoiceScope.open))
            Text("Overdue").tag(Optional(InvoiceScope.overdue))
            Text("All").tag(Optional(InvoiceScope.all))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Which invoices")
    }

    private var scopeBinding: Binding<InvoiceScope?> {
        Binding(
            get: {
                switch filter {
                case .open: .open
                case .overdue: .overdue
                case .all: .all
                case .notYetDue, .collected: nil
                }
            },
            set: { newValue in
                switch newValue {
                case .open: filter = .open
                case .overdue: filter = .overdue
                case .all: filter = .all
                case nil: break
                }
            }
        )
    }

    private var list: some View {
        Group {
            if rows.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { item in
                            DashboardLedgerRow(
                                invoice: item.invoice,
                                periodCollected: item.periodCollected,
                                onSelect: { select(item.invoice) },
                                onPay: { paymentInvoice = item.invoice },
                                onOpen: { onOpenInvoice(item.invoice.persistentModelID) }
                            )
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(emptyTitle)
                .font(.headline)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private var rows: [DashboardLedgerItem] {
        DashboardMath.ledgerItems(invoices, receipts: receipts, filter: filter, search: search)
    }

    private var countCaption: String {
        let count = rows.count
        let noun = count == 1 ? "invoice" : "invoices"
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return count == 1 ? "1 match" : "\(count) matches"
        }
        return "\(filterTitle) · \(count) \(noun)"
    }

    private var filterTitle: String {
        switch filter {
        case .open:
            return "Open"
        case .notYetDue:
            return "Not yet due"
        case .overdue:
            return "Overdue"
        case .all:
            return "All"
        case .collected(let window, let start):
            if let start, let label = buckets.first(where: { $0.start == start })?.label {
                return "\(window.spokenTitle) · \(label)"
            }
            return window.spokenTitle
        }
    }

    private var emptyTitle: String {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matches" }
        return switch filter {
        case .open: "No open invoices"
        case .notYetDue: "Nothing waiting"
        case .overdue: "Nothing overdue"
        case .all: "No invoices"
        case .collected: "No payments in this period"
        }
    }

    private var emptyMessage: String {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try another number, client, or job."
        }
        return switch filter {
        case .open: "Everything on the books is settled, or nothing has been written yet."
        case .notYetDue: "Open invoices are all past due."
        case .overdue: "No balance is past its due date."
        case .all: "Write one when a job is ready to bill."
        case .collected: "No invoice was paid in this stretch."
        }
    }

    private func select(_ invoice: Invoice) {
        if invoice.canEditLines {
            editingInvoice = invoice
        } else {
            onOpenInvoice(invoice.persistentModelID)
        }
    }
}
