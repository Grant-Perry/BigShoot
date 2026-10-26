import SwiftData
import SwiftUI

enum InvoiceScope: String, CaseIterable, Identifiable {
    case open
    case overdue
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open"
        case .overdue: "Overdue"
        case .all: "All"
        }
    }

    /// Open is every invoice that has not been paid. Void invoices are off the books.
    func includes(_ invoice: Invoice) -> Bool {
        switch self {
        case .open:
            invoice.holdsOpenBalance
        case .overdue:
            invoice.displayStatus == .overdue
        case .all:
            true
        }
    }
}

struct InvoiceWorkspace: View {
    @Binding var selection: PersistentIdentifier?
    @Binding var showNewInvoice: Bool
    var onOpenInvoice: (PersistentIdentifier) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Invoice.invoiceDate, order: .reverse) private var invoices: [Invoice]
    @State private var scope: InvoiceScope = .open
    @State private var search = ""
    @State private var paymentInvoice: Invoice?
    @State private var previewInvoice: Invoice?
    @State private var editingInvoice: Invoice?
    @State private var mailNote: String?
    @State private var deletePrompt: DeletePrompt?
    @State private var booksError: String?
    @State private var showTrail = false

    private var filtered: [Invoice] {
        invoices.filter { invoice in
            guard scope.includes(invoice) else { return false }
            guard !search.isEmpty else { return true }
            return invoice.displayNumber.localizedStandardContains(search)
                || invoice.clientName.localizedStandardContains(search)
                || invoice.number.localizedStandardContains(search)
                || invoice.job?.name.localizedStandardContains(search) == true
        }
    }

    private var selected: Invoice? {
        invoices.first { $0.persistentModelID == selection }
    }

    var body: some View {
        HStack(spacing: 0) {
            invoiceList
                .frame(width: 380)
            Divider()
            Group {
                if let selected {
                    InvoiceDetailView(
                        invoice: selected,
                        onRecordPayment: { paymentInvoice = selected },
                        onPreview: { previewInvoice = selected },
                        onRemind: { remind(selected) },
                        onEdit: { editingInvoice = selected },
                        onMarkSent: { markSent(selected) },
                        onDelete: { askToDelete(selected) }
                    )
                } else {
                    StudioEmptyState(
                        title: "No invoice selected",
                        message: "Open a balance, or write a new invoice from the catalog.",
                        symbol: "doc.text"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioSceneBackground())
        }
        .onDeleteCommand {
            if let selected { askToDelete(selected) }
        }
        .sheet(item: $paymentInvoice) { invoice in
            RecordPaymentSheet(invoice: invoice)
        }
        .sheet(item: $previewInvoice) { invoice in
            InvoicePDFPreviewSheet(invoice: invoice, note: nil) {
                submit(invoice)
            }
        }
        .sheet(item: $editingInvoice) { invoice in
            NewInvoiceSheet(existing: invoice, onOpenInvoice: onOpenInvoice)
        }
        .sheet(isPresented: $showTrail) {
            BooksHistorySheet()
        }
        .alert(
            deletePrompt?.title ?? "Delete invoice?",
            isPresented: deletePresented,
            presenting: deletePrompt
        ) { prompt in
            Button("Delete", role: .destructive) { confirmDelete(prompt) }
            Button("Cancel", role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
        .alert("Couldn’t update the books", isPresented: booksErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(booksError ?? "")
        }
        .alert("Mail", isPresented: mailPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mailNote ?? "")
        }
    }

    private var mailPresented: Binding<Bool> {
        Binding(get: { mailNote != nil }, set: { if !$0 { mailNote = nil } })
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deletePrompt != nil }, set: { if !$0 { deletePrompt = nil } })
    }

    private var booksErrorPresented: Binding<Bool> {
        Binding(get: { booksError != nil }, set: { if !$0 { booksError = nil } })
    }

    private var invoiceList: some View {
        VStack(spacing: 0) {
            scopePicker
            StudioColumnSearch(text: $search, prompt: "Number, client, or job", findLabel: "Find Invoice")
            List(filtered, selection: $selection) { invoice in
                InvoiceListRow(invoice: invoice)
                    .tag(invoice.persistentModelID)
                    .contextMenu {
                        InvoiceContextMenu(
                            invoice: invoice,
                            onRecordPayment: { begin(invoice) { paymentInvoice = invoice } },
                            onEdit: { begin(invoice) { editingInvoice = invoice } },
                            onPreview: { begin(invoice) { previewInvoice = invoice } },
                            onRemind: { begin(invoice) { remind(invoice) } },
                            onMarkSent: { begin(invoice) { markSent(invoice) } },
                            onDelete: { begin(invoice) { askToDelete(invoice) } }
                        )
                    }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if filtered.isEmpty {
                    StudioEmptyState(title: emptyTitle, message: emptyMessage, symbol: "doc.text")
                }
            }
        }
        .navigationTitle("Invoices")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Audit Trail", systemImage: "clock.arrow.circlepath") { showTrail = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Invoice", systemImage: "plus") { showNewInvoice = true }
            }
        }
    }

    private var scopePicker: some View {
        Picker("Show", selection: $scope) {
            ForEach(InvoiceScope.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private var emptyTitle: String {
        if !search.isEmpty { return "No matches" }
        switch scope {
        case .open: return "No open invoices"
        case .overdue: return "Nothing overdue"
        case .all: return "No invoices"
        }
    }

    private var emptyMessage: String {
        if !search.isEmpty { return "Try another number, client, or job." }
        switch scope {
        case .open: return "Every balance on the books is settled."
        case .overdue: return "Every open balance is still on time."
        case .all: return "Write a new invoice from the catalog."
        }
    }

    private func begin(_ invoice: Invoice, action: () -> Void) {
        selection = invoice.persistentModelID
        action()
    }

    private func askToDelete(_ invoice: Invoice) {
        deletePrompt = DeletePrompt(
            invoiceID: invoice.persistentModelID,
            title: InvoiceRemoval.title(for: invoice),
            message: InvoiceRemoval.message(for: invoice)
        )
    }

    private func confirmDelete(_ prompt: DeletePrompt) {
        guard let invoice = invoices.first(where: { $0.persistentModelID == prompt.invoiceID }) else { return }
        do {
            try InvoiceRemoval.remove(invoice, in: modelContext)
            if selection == prompt.invoiceID { selection = nil }
        } catch {
            booksError = error.localizedDescription
        }
    }

    private func remind(_ invoice: Invoice) {
        if invoice.remindersDisabled {
            mailNote = "Reminders are turned off for this invoice. You can still preview the PDF."
            previewInvoice = invoice
            return
        }
        switch ReminderComposer.compose(invoice: invoice) {
        case .composed:
            break
        case .unavailable:
            mailNote = "Mail isn’t available. Save the PDF and send it yourself."
            previewInvoice = invoice
        }
    }

    private func submit(_ invoice: Invoice) {
        invoice.submittedAt = .now
        BooksTrail.noteSubmitted(invoice, in: modelContext)
        do {
            try modelContext.save()
        } catch {
            booksError = error.localizedDescription
        }
    }

    private func markSent(_ invoice: Invoice) {
        if invoice.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invoice.number = InvoiceMath.nextNumber(among: invoices.map(\.number))
        }
        invoice.status = .pending
        InvoiceMath.applyDerivedStatus(invoice)
        BooksTrail.noteMarkedSent(invoice, in: modelContext)
        do {
            try modelContext.save()
        } catch {
            booksError = error.localizedDescription
        }
    }
}

private struct DeletePrompt {
    var invoiceID: PersistentIdentifier
    var title: String
    var message: String
}
