import SwiftData
import SwiftUI

struct JobDetailView: View {
    var job: Job
    var onOpenInvoice: (PersistentIdentifier) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.displayName)
                        .font(StudioDesign.displayTitle)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                .textSelection(.enabled)
                VStack(alignment: .leading, spacing: 8) {
                    row("Date", StudioDay.string(job.eventDate))
                    row("Type", job.jobType.isEmpty ? "—" : job.jobType)
                    row("Status", job.status.isEmpty ? "—" : job.status.replacingOccurrences(of: "_", with: " "))
                    row("People", job.contact?.displayName ?? "No one is linked")
                    if let email = job.contact?.email, !email.isEmpty {
                        row("Email", email)
                    }
                }
                .padding(StudioDesign.Spacing.card)
                .paperCard()
                .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Invoices", systemImage: "doc.text")
                        .font(.headline)
                    if job.invoices.isEmpty {
                        Text("No invoices for this job.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(job.invoices.sorted { $0.invoiceDate > $1.invoiceDate }) { invoice in
                            Button {
                                onOpenInvoice(invoice.persistentModelID)
                            } label: {
                                HStack {
                                    Text(invoice.displayNumber)
                                    StatusBadge(status: invoice.displayStatus)
                                    Spacer()
                                    Text(StudioMoney.string(invoice.balance))
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(StudioDesign.Spacing.workspace)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var subtitle: String {
        [job.jobType, StudioDay.string(job.eventDate)].filter { !$0.isEmpty && $0 != "—" }.joined(separator: " · ")
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .frame(width: 90, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }
}

struct JobEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let contacts: [Contact]

    @State private var name = ""
    @State private var jobType = "Wedding"
    @State private var eventDate = Date.now
    @State private var hasDate = true
    @State private var contact: Contact?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New job")
                .font(StudioDesign.displayTitle)
            Form {
                TextField("Name", text: $name)
                TextField("Type", text: $jobType)
                Toggle("Event date", isOn: $hasDate)
                if hasDate {
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                }
                ContactPickerField(contacts: contacts, selection: $contact)
            }
            .formStyle(.grouped)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || contact == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func save() {
        let job = Job(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            eventDate: hasDate ? eventDate : nil,
            jobType: jobType.trimmingCharacters(in: .whitespacesAndNewlines),
            status: "active",
            contact: contact
        )
        modelContext.insert(job)
        try? modelContext.save()
        dismiss()
    }
}

struct ContactPickerField: View {
    let contacts: [Contact]
    @Binding var selection: Contact?
    @State private var query = ""

    private var matches: [Contact] {
        let active = contacts.filter { !$0.archived }
        guard !query.isEmpty else { return Array(active.prefix(6)) }
        return active.filter {
            $0.displayName.localizedStandardContains(query) || $0.email.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Client", text: $query)
            if selection?.displayName != query {
                ForEach(matches.prefix(6)) { contact in
                    Button {
                        selection = contact
                        query = contact.displayName
                    } label: {
                        VStack(alignment: .leading) {
                            Text(contact.displayName)
                            if !contact.email.isEmpty {
                                Text(contact.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { query = selection?.displayName ?? "" }
    }
}
