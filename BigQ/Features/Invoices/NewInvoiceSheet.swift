import SwiftData
import SwiftUI

struct NewInvoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.fullName) private var contacts: [Contact]
    @Query(sort: \CatalogItem.name) private var catalog: [CatalogItem]
    @Query(sort: \TaxSchedule.name) private var schedules: [TaxSchedule]

    var existing: Invoice?
    var onOpenInvoice: (PersistentIdentifier) -> Void
    @State private var draft = InvoiceDraftModel()
    @State private var errorMessage: String?
    @State private var jobEditor: JobEditorLaunch?
    @State private var additionalWorkJobID: PersistentIdentifier?
    @State private var bypassPrompt: JobBypass?
    @State private var previewSession: InvoicePreviewSession?
    @State private var confirmPipelineSave = false
    @State private var pendingMarkSent = false

    private var jobs: [Job] {
        var list = draft.contact?.jobs ?? []
        if let job = draft.job,
           job.contact?.persistentModelID == draft.contact?.persistentModelID,
           !list.contains(where: { $0.persistentModelID == job.persistentModelID }) {
            list.append(job)
        }
        return list.sorted { ($0.eventDate ?? .distantPast) > ($1.eventDate ?? .distantPast) }
    }

    var body: some View {
        @Bindable var draft = draft
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text(editorTitle)
                    .font(StudioDesign.displayTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let submitted = draft.submittedAt {
                    SubmittedDatePill(date: submitted)
                }
                Button("Preview", systemImage: "doc.richtext", action: showPreview)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("See the invoice PDF without saving")
            }
            if let submitted = draft.pipelineSubmittedAt {
                InvoicePipelineNotice(submittedAt: submitted)
            }
            clientColumn
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InvoiceLinesEditor(draft: draft, catalog: catalog)
                .frame(maxWidth: .infinity)
            footer
        }
        .padding(24)
        .frame(width: 860)
        .fixedSize(horizontal: false, vertical: true)
        .studioActive()
        .focusedSceneValue(\.invoiceEditorActive, true)
        .onAppear {
            if let existing { draft.load(existing) }
        }
        .sheet(item: $jobEditor) { launch in
            JobEditorSheet(contacts: contacts, contact: draft.contact, job: launch.job) { saved in
                draft.contact = saved.contact ?? draft.contact
                draft.job = saved
            }
        }
        .sheet(item: $previewSession) { session in
            InvoicePDFPreviewSheet(invoice: session.invoice, note: nil, onSubmit: submitFromPreview)
        }
        .alert("Overwrite this submission?", isPresented: $confirmPipelineSave) {
            Button("Save Anyway", role: .destructive) {
                commitSave(markSent: pendingMarkSent)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let submitted = draft.pipelineSubmittedAt {
                Text("This invoice was submitted \(StudioStamp.string(submitted)). Saving replaces what’s already in the pipeline.")
            }
        }
    }

    private func submitFromPreview() {
        let stamp = Date.now
        draft.noteSubmitted(stamp)
        guard let existing else { return }
        existing.submittedAt = stamp
        BooksTrail.noteSubmitted(existing, in: modelContext)
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func showPreview() {
        let studio = existing?.studio ?? (try? StudioBrandDirectory.primary(in: modelContext))
        do {
            previewSession = try draft.makePreview(studio: studio)
        } catch {
            errorMessage = "Couldn’t open the preview."
        }
    }

    private var clientColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                ContactPickerField(contacts: contacts, selection: $draft.contact, label: "Client:")
                    .frame(maxWidth: .infinity, alignment: .leading)
                JobMenuPicker(
                    jobs: jobs,
                    selection: draft.job,
                    openBalance: openBalanceLabels,
                    placeEscapesLast: contactHasOpenInvoice,
                    onAdd: { presentJobEditor(nil) },
                    onSelect: selectJob,
                    onEdit: presentJobEditor
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            jobNotice
            HStack(alignment: .top, spacing: 20) {
                DatePicker("Invoice date:", selection: $draft.invoiceDate, displayedComponents: .date)
                DatePicker("Due:", selection: $draft.dueDate, displayedComponents: .date)
                VStack(alignment: .leading, spacing: 8) {
                    NetDaysField(days: $draft.netDays)
                    InvoiceSubmittedField(submittedAt: $draft.submittedAt)
                }
                Spacer(minLength: 0)
            }
            InvoiceTaxControls(draft: draft, schedules: schedules)
            HStack(alignment: .top, spacing: 20) {
                invoiceText(
                    "Note:",
                    prompt: "Prints on the invoice",
                    text: $draft.note,
                    help: "Prints in small type above the sign-off."
                )
                invoiceText(
                    "Sign-off:",
                    prompt: "Thank you.",
                    text: $draft.closing,
                    help: "Prints at the bottom. Leave blank for Thank you."
                )
            }
        }
        .onChange(of: draft.netDays) { _, _ in
            draft.applyNetDays()
        }
        .onChange(of: draft.dueDate) { _, _ in
            draft.syncNetDaysFromDueDate()
        }
        .onChange(of: draft.invoiceDate) { _, _ in
            guard draft.job?.eventDate == nil else { return }
            draft.applyNetDays()
        }
        .onChange(of: draft.job?.persistentModelID) { _, _ in
            draft.applyNetDays()
            draft.fillEmptyNoteFromJob()
        }
        .onChange(of: draft.job?.name) { _, _ in
            draft.fillEmptyNoteFromJob()
        }
        .onChange(of: draft.job?.eventDate) { _, _ in
            draft.applyNetDays()
        }
        .onChange(of: draft.contact?.persistentModelID) { _, _ in
            bypassPrompt = nil
            additionalWorkJobID = nil
            if let job = draft.job, job.contact?.persistentModelID != draft.contact?.persistentModelID {
                draft.job = nil
            }
        }
    }

    private var editorTitle: String {
        guard draft.isEditing else { return "New invoice" }
        let number = draft.titleNumber
        guard !number.isEmpty else { return "Edit invoice" }
        return "Edit invoice: \(number)"
    }

    private func invoiceText(
        _ title: String,
        prompt: String,
        text: Binding<String>,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(prompt, text: text, axis: .vertical)
                .lineLimit(2, reservesSpace: true)
        }
        .help(help)
    }

    @ViewBuilder
    private var jobNotice: some View {
        if let bypassPrompt, contactHasOpenInvoice {
            OpenInvoiceGuard(
                title: openInvoiceTitle(count: contactOpenInvoices.count, subject: "client"),
                invoices: contactOpenInvoices,
                showsJobName: true,
                continueTitle: bypassPrompt.continueTitle,
                onOpen: openExisting,
                onContinue: confirmBypass
            )
        } else if let job = draft.job, !openInvoicesOnJob.isEmpty, !draft.isEditing {
            if additionalWorkJobID == job.persistentModelID {
                OpenInvoiceAcknowledgement(invoices: openInvoicesOnJob, onOpen: openExisting)
            } else {
                OpenInvoiceGuard(
                    title: openInvoiceTitle(count: openInvoicesOnJob.count, subject: "job"),
                    invoices: openInvoicesOnJob,
                    showsJobName: false,
                    continueTitle: "This is additional work",
                    onOpen: openExisting,
                    onContinue: allowAdditionalWork
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            if draft.editingSentInvoice {
                saveSentInvoiceButton
            } else {
                Button("Save Draft") { save(markSent: false) }
                    .disabled(!canCommit)
                saveSentButton
            }
        }
    }

    @ViewBuilder
    private var saveSentInvoiceButton: some View {
        let button = Button("Save") { save(markSent: false) }
            .disabled(!canCommit)
        if canCommit {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }

    @ViewBuilder
    private var saveSentButton: some View {
        let button = Button("Save & Mark Sent") { save(markSent: true) }
            .disabled(!canCommit)
        if canCommit {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }

    private var openInvoicesOnJob: [Invoice] {
        guard !draft.isEditing, let job = draft.job else { return [] }
        return job.invoicesWithOpenBalance
    }

    private var contactOpenInvoices: [Invoice] {
        jobs
            .flatMap(\.invoicesWithOpenBalance)
            .sorted { $0.invoiceDate > $1.invoiceDate }
    }

    private var contactHasOpenInvoice: Bool {
        !draft.isEditing && !contactOpenInvoices.isEmpty
    }

    private var openBalanceLabels: [PersistentIdentifier: String] {
        Dictionary(uniqueKeysWithValues: jobs.compactMap { job in
            let open = job.invoicesWithOpenBalance
            guard let first = open.first else { return nil }
            let label = open.count == 1
                ? "Open · \(StudioMoney.string(first.balance))"
                : "\(open.count) open"
            return (job.persistentModelID, label)
        })
    }

    private var canCommit: Bool {
        guard draft.canSave, bypassPrompt == nil else { return false }
        guard !openInvoicesOnJob.isEmpty else { return true }
        return additionalWorkJobID == draft.job?.persistentModelID
    }

    private func openInvoiceTitle(count: Int, subject: String) -> String {
        count == 1
            ? "This \(subject) already has an open invoice"
            : "This \(subject) already has open invoices"
    }

    private func selectJob(_ job: Job?) {
        if job == nil, contactHasOpenInvoice {
            bypassPrompt = .noJob
            return
        }
        bypassPrompt = nil
        draft.job = job
    }

    private func presentJobEditor(_ job: Job?) {
        if job == nil, contactHasOpenInvoice {
            bypassPrompt = .newJob
            return
        }
        showJobEditor(job)
    }

    private func confirmBypass() {
        let prompt = bypassPrompt
        bypassPrompt = nil
        switch prompt {
        case .newJob:
            showJobEditor(nil)
        case .noJob:
            draft.job = nil
        case nil:
            break
        }
    }

    private func allowAdditionalWork() {
        additionalWorkJobID = draft.job?.persistentModelID
    }

    private func openExisting(_ invoice: Invoice) {
        onOpenInvoice(invoice.persistentModelID)
        dismiss()
    }

    private func showJobEditor(_ job: Job?) {
        Task { @MainActor in
            jobEditor = JobEditorLaunch(job: job)
        }
    }

    private func save(markSent: Bool) {
        draft.commitTaxRate(schedules: schedules)
        guard canCommit else { return }
        if draft.isMissingTaxRate {
            draft.invoiceTaxable = true
            errorMessage = InvoiceDraftError.missingTaxRate.localizedDescription
            return
        }
        if draft.pipelineSubmittedAt != nil {
            pendingMarkSent = markSent
            confirmPipelineSave = true
            return
        }
        commitSave(markSent: markSent)
    }

    private func commitSave(markSent: Bool) {
        do {
            _ = try draft.save(in: modelContext, markSent: markSent)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum JobBypass {
    case newJob
    case noJob

    var continueTitle: String {
        switch self {
        case .newJob: "Add a job anyway"
        case .noJob: "Continue without a job"
        }
    }
}

private struct JobEditorLaunch: Identifiable {
    let id = UUID()
    var job: Job?
}

private struct SubmittedDatePill: View {
    var date: Date

    var body: some View {
        Text("Submitted: \(StudioStamp.string(date))")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.gpGreen.opacity(0.18), in: Capsule())
            .foregroundStyle(Color.gpGreen)
            .accessibilityLabel("Submitted \(StudioStamp.string(date))")
    }
}

private struct NetDaysField: View {
    @Binding var days: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("Net:")
                .accessibilityHidden(true)
            TextField("Days", value: $days, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .accessibilityLabel("Net days")
            Stepper("Adjust net days", value: $days, step: 15)
                .labelsHidden()
            Text("days")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .fixedSize()
    }
}

