import SwiftData
import SwiftUI

struct JobDetailView: View {
    @Environment(\.modelContext) private var modelContext
    var job: Job
    var contacts: [Contact]
    var onEdit: () -> Void = {}
    var onAddContract: () -> Void = {}
    var onEditContract: (Contract) -> Void = { _ in }
    var onDeleteContract: (Contract) -> Void = { _ in }
    var onOpenInvoice: (PersistentIdentifier) -> Void
    var onOpenQuote: (PersistentIdentifier) -> Void = { _ in }

    @State private var types = JobTypeCatalog()
    @State private var typeTag = JobTypeMenuTag.type(JobTypeCatalog.commercial)
    @State private var showAddType = false
    @State private var newTypeName = ""
    @State private var contactEditor: ContactEditorMode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Job name", text: nameBinding)
                        .font(StudioDesign.displayTitle)
                        .textFieldStyle(.plain)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }

                detailsCard

                ContractListSection(
                    contracts: ContractLinks.forJob(job),
                    emptyMessage: "No contracts for this job.",
                    onAdd: onAddContract,
                    onEdit: onEditContract,
                    onDelete: onDeleteContract
                )
                .padding(StudioDesign.Spacing.card)
                .frame(maxWidth: .infinity, alignment: .leading)
                .studioCard()

                JobPaymentTermsSection(job: job)
                    .padding(StudioDesign.Spacing.card)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .studioCard()

                linkedSection("Quotes", symbol: "doc.plaintext") {
                    if job.quotes.isEmpty {
                        Text("No quotes for this job.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(job.quotes.sorted { $0.quoteDate > $1.quoteDate }) { quote in
                            Button {
                                onOpenQuote(quote.persistentModelID)
                            } label: {
                                HStack {
                                    Text(quote.displayNumber)
                                    QuoteStatusBadge(status: quote.status)
                                    Spacer()
                                    Text(StudioMoney.string(quote.total))
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                linkedSection("Invoices", symbol: "doc.text") {
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
            .padding(StudioDesign.Spacing.card)
            .frame(maxWidth: 760, alignment: .leading)
            .studioCard()
            .padding(StudioDesign.Spacing.workspace)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil", action: onEdit)
            }
            ToolbarItem {
                Button("Add Contract", systemImage: "signature", action: onAddContract)
            }
        }
        .onAppear(perform: syncTypeTag)
        .onChange(of: job.persistentModelID) { _, _ in
            syncTypeTag()
        }
        .sheet(item: $contactEditor) { mode in
            ContactEditorSheet(mode: mode) { saved in
                job.contact = saved
                persist()
            }
        }
        .alert("Add Type", isPresented: $showAddType) {
            TextField("Type", text: $newTypeName)
            Button("Add", action: commitNewType)
            Button("Cancel", role: .cancel) { newTypeName = "" }
        }
    }

    private var subtitle: String {
        [job.jobType, StudioDay.string(job.eventDate)]
            .filter { !$0.isEmpty && $0 != "—" }
            .joined(separator: " · ")
    }

    private var typeChoices: [String] {
        var names = types.names
        let current = job.jobType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return names }
        if !names.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            names.append(current)
        }
        return names
    }

    private var statusChoices: [String] {
        var names = ["active", "completed", "cancelled", "archived"]
        let current = job.status.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty,
           !names.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            names.insert(current, at: 0)
        }
        return names
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { job.name },
            set: {
                job.name = $0
                persist()
            }
        )
    }

    private var eventDateBinding: Binding<Date> {
        Binding(
            get: { job.eventDate ?? .now },
            set: {
                job.eventDate = $0
                persist()
            }
        )
    }

    private var statusBinding: Binding<String> {
        Binding(
            get: {
                let current = job.status.trimmingCharacters(in: .whitespacesAndNewlines)
                return current.isEmpty ? "active" : current
            },
            set: {
                job.status = $0
                job.archived = $0.localizedStandardContains("archived")
                persist()
            }
        )
    }

    private var contactBinding: Binding<Contact?> {
        Binding(
            get: { job.contact },
            set: {
                job.contact = $0
                persist()
            }
        )
    }

    private var emailBinding: Binding<String> {
        Binding(
            get: { job.contact?.email ?? "" },
            set: { next in
                guard let contact = job.contact else { return }
                contact.email = next
                persist()
            }
        )
    }

    private func syncTypeTag() {
        let stored = job.jobType.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = types.names.first { $0.caseInsensitiveCompare(stored) == .orderedSame }
            ?? (stored.isEmpty ? JobTypeCatalog.commercial : stored)
        typeTag = .type(resolved)
    }

    private func handleTypeTag(_ tag: JobTypeMenuTag) {
        switch tag {
        case .add:
            showAddType = true
            let revert = JobTypeMenuTag.type(
                job.jobType.isEmpty ? JobTypeCatalog.commercial : job.jobType
            )
            Task { @MainActor in
                if typeTag == .add {
                    typeTag = revert
                }
            }
        case .type(let name):
            job.jobType = name
            persist()
        }
    }

    private func commitNewType() {
        defer { newTypeName = "" }
        guard let name = types.add(newTypeName) else { return }
        job.jobType = name
        typeTag = .type(name)
        persist()
    }

    private func persist() {
        try? modelContext.save()
    }

    private var detailsCard: some View {
        StudioLabeledStack {
            StudioLabeledRow("Event Date") {
                DatePicker(
                    "",
                    selection: eventDateBinding,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.field)
            }
            StudioLabeledRow("Type") {
                Picker("", selection: $typeTag) {
                    Label("Add Type", systemImage: "plus").tag(JobTypeMenuTag.add)
                    Divider()
                    ForEach(typeChoices, id: \.self) { name in
                        Text(name).tag(JobTypeMenuTag.type(name))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: typeTag) { _, tag in
                    handleTypeTag(tag)
                }
            }
            StudioLabeledRow("Status") {
                Picker("", selection: statusBinding) {
                    ForEach(statusChoices, id: \.self) { status in
                        Text(status.replacingOccurrences(of: "_", with: " ")).tag(status)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            StudioLabeledRow("Client") {
                ContactPickerField(
                    contacts: contacts,
                    selection: contactBinding,
                    label: "Client",
                    showsLabel: false,
                    onAdd: { contactEditor = .new }
                )
            }
            StudioLabeledRow("Email") {
                TextField("Email", text: emailBinding)
                    .textFieldStyle(.roundedBorder)
                    .disabled(job.contact == nil)
            }
            if let phone = job.contact?.phone, !phone.isEmpty {
                StudioLabeledRow("Phone") {
                    Text(phone)
                        .textSelection(.enabled)
                }
            }
            if let address = job.contact?.address, !address.isEmpty {
                StudioLabeledRow("Address") {
                    Text(address)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private func linkedSection<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
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
    @State private var contactEditor: ContactEditorMode?
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
                    DatePicker("Event Date", selection: $eventDate, displayedComponents: .date)
                }
                ContactPickerField(
                    contacts: contacts,
                    selection: $contact,
                    onAdd: { contactEditor = .new }
                )
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
        .studioActive()
        .sheet(item: $contactEditor) { mode in
            ContactEditorSheet(mode: mode) { saved in
                contact = saved
            }
        }
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

enum JobTypeMenuTag: Hashable {
    case add
    case type(String)
}
