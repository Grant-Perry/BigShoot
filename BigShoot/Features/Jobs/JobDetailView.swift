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
    let job: Job?
    var onSave: (Job) -> Void

    @State private var name = ""
    @State private var types = JobTypeCatalog()
    @State private var jobType = JobTypeCatalog.commercial
    @State private var typeTag = JobTypeMenuTag.type(JobTypeCatalog.commercial)
    @State private var showAddType = false
    @State private var newTypeName = ""
    @State private var eventDate = Date.now
    @State private var hasDate = true
    @State private var contact: Contact?
    @FocusState private var nameFocused: Bool

    init(contacts: [Contact], contact: Contact? = nil, job: Job? = nil, onSave: @escaping (Job) -> Void = { _ in }) {
        self.contacts = contacts
        self.job = job
        self.onSave = onSave
        let catalog = JobTypeCatalog()
        let storedType = job?.jobType.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedType = catalog.names.first { $0.caseInsensitiveCompare(storedType) == .orderedSame }
            ?? (storedType.isEmpty ? JobTypeCatalog.commercial : storedType)
        _types = State(initialValue: catalog)
        _name = State(initialValue: job?.name ?? "")
        _jobType = State(initialValue: resolvedType)
        _typeTag = State(initialValue: .type(resolvedType))
        _hasDate = State(initialValue: job == nil || job?.eventDate != nil)
        _eventDate = State(initialValue: job?.eventDate ?? .now)
        _contact = State(initialValue: job?.contact ?? contact)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(job == nil ? "New job" : "Edit job")
                .font(StudioDesign.displayTitle)
            Form {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                Picker("Type", selection: $typeTag) {
                    Label("Add Type", systemImage: "plus").tag(JobTypeMenuTag.add)
                    Divider()
                    ForEach(typeChoices, id: \.self) { name in
                        Text(name).tag(JobTypeMenuTag.type(name))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: typeTag) { _, tag in
                    handleTypeTag(tag)
                }
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
        .alert("Add Type", isPresented: $showAddType) {
            TextField("Type", text: $newTypeName)
            Button("Add", action: commitNewType)
            Button("Cancel", role: .cancel) { newTypeName = "" }
        }
        .onAppear { nameFocused = true }
    }

    private var typeChoices: [String] {
        var names = types.names
        let current = jobType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return names }
        if !names.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            names.append(current)
        }
        return names
    }

    private func handleTypeTag(_ tag: JobTypeMenuTag) {
        switch tag {
        case .add:
            showAddType = true
            let revert = JobTypeMenuTag.type(jobType)
            Task { @MainActor in
                if typeTag == .add {
                    typeTag = revert
                }
            }
        case .type(let name):
            jobType = name
        }
    }

    private func commitNewType() {
        defer { newTypeName = "" }
        guard let name = types.add(newTypeName) else { return }
        jobType = name
        typeTag = .type(name)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = jobType.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = hasDate ? eventDate : nil
        let saved: Job
        if let job {
            job.name = trimmedName
            job.jobType = trimmedType
            job.eventDate = date
            job.contact = contact
            saved = job
        } else {
            saved = Job(
                name: trimmedName,
                eventDate: date,
                jobType: trimmedType,
                status: "active",
                contact: contact
            )
            modelContext.insert(saved)
        }
        try? modelContext.save()
        onSave(saved)
        dismiss()
    }
}

private enum JobTypeMenuTag: Hashable {
    case add
    case type(String)
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
