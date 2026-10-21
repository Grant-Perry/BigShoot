import SwiftData
import SwiftUI

struct NewInvoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.fullName) private var contacts: [Contact]
    @Query(sort: \CatalogItem.name) private var catalog: [CatalogItem]

    var existing: Invoice?
    @State private var draft = InvoiceDraftModel()
    @State private var catalogQuery = ""
    @State private var errorMessage: String?

    private var jobs: [Job] {
        guard let contact = draft.contact else { return [] }
        return contact.jobs.sorted { ($0.eventDate ?? .distantPast) > ($1.eventDate ?? .distantPast) }
    }

    private var catalogMatches: [CatalogItem] {
        guard !catalogQuery.isEmpty else { return Array(catalog.prefix(8)) }
        return catalog.filter { $0.name.localizedStandardContains(catalogQuery) }
    }

    var body: some View {
        @Bindable var draft = draft
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.isEditing ? "Edit invoice" : "New invoice")
                .font(StudioDesign.displayTitle)
            HStack(alignment: .top, spacing: 20) {
                clientColumn
                    .frame(width: 280)
                linesColumn
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            footer
        }
        .padding(24)
        .frame(minWidth: 860, minHeight: 640)
        .onAppear {
            if let existing { draft.load(existing) }
        }
    }

    private var clientColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContactPickerField(contacts: contacts, selection: $draft.contact)
            Picker("Job", selection: jobSelection) {
                Text("No job").tag(PersistentIdentifier?.none)
                ForEach(jobs) { job in
                    Text(job.displayName).tag(Optional(job.persistentModelID))
                }
            }
            DatePicker("Invoice date", selection: $draft.invoiceDate, displayedComponents: .date)
            DatePicker("Due", selection: $draft.dueDate, displayedComponents: .date)
            TextField("Tax", value: $draft.tax, format: .number.precision(.fractionLength(2)))
            TextField("Note", text: $draft.note, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var linesColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Add from catalog", text: $catalogQuery)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(catalogMatches.prefix(8)) { item in
                        Button {
                            draft.addCatalogItem(item)
                            catalogQuery = ""
                        } label: {
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(StudioMoney.string(item.defaultPrice))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 140)
            Divider()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach($draft.lines) { $line in
                        InvoiceLineEditor(line: $line) {
                            draft.lines.removeAll { $0.id == line.id }
                        }
                    }
                }
            }
            Button("Add a blank line", systemImage: "plus", action: draft.addBlankLine)
                .buttonStyle(.borderless)
        }
        .padding(StudioDesign.Spacing.card)
        .paperCard()
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Total \(StudioMoney.string(draft.total))")
                    .font(StudioDesign.metric(20))
                    .monospacedDigit()
                Text("Subtotal \(StudioMoney.string(draft.subtotal)) · Tax \(StudioMoney.string(draft.tax))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Save Draft") { save(markSent: false) }
                .disabled(!draft.canSave)
            Button("Save & Mark Sent") { save(markSent: true) }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSave)
        }
    }

    private var jobSelection: Binding<PersistentIdentifier?> {
        Binding {
            draft.job?.persistentModelID
        } set: { id in
            draft.job = jobs.first { $0.persistentModelID == id }
        }
    }

    private func save(markSent: Bool) {
        do {
            _ = try draft.save(in: modelContext, markSent: markSent)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct InvoiceLineEditor: View {
    @Binding var line: DraftLine
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Name", text: $line.name)
                TextField("Qty", value: $line.quantity, format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 70)
                TextField("Price", value: $line.unitPrice, format: .number.precision(.fractionLength(2)))
                    .frame(width: 100)
                Text(StudioMoney.string(line.lineTotal))
                    .frame(width: 90, alignment: .trailing)
                    .monospacedDigit()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
            TextField("Detail", text: $line.detail)
                .font(.caption)
        }
    }
}
