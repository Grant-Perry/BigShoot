import SwiftData
import SwiftUI

/// Pricing-only quote editor. Agreement lives in `QuoteAgreementSheet` —
/// nesting NSTextView here caused layout clipping and main-thread beachballs.
struct NewQuoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.fullName) private var contacts: [Contact]
    @Query(sort: \CatalogItem.name) private var catalog: [CatalogItem]
    @Query(sort: \TaxSchedule.name) private var schedules: [TaxSchedule]
    @Query private var quotes: [Quote]

    var existing: Quote?
    @State private var draft: QuoteDraftModel
    @State private var errorMessage: String?
    @State private var jobEditor: JobEditorLaunch?
    @State private var contactEditor: ContactEditorMode?
    @State private var previewSession: QuotePreviewSession?
    @State private var includeValidUntil: Bool

    init(existing: Quote? = nil) {
        self.existing = existing
        if let existing {
            let loaded = QuoteDraftModel()
            loaded.load(existing)
            _draft = State(initialValue: loaded)
            _includeValidUntil = State(initialValue: existing.validUntil != nil)
        } else {
            _draft = State(initialValue: QuoteDraftModel())
            _includeValidUntil = State(initialValue: false)
        }
    }

    private var jobs: [Job] {
        var list = draft.pricing.contact?.jobs ?? []
        if let job = draft.pricing.job,
           job.contact?.persistentModelID == draft.pricing.contact?.persistentModelID,
           !list.contains(where: { $0.persistentModelID == job.persistentModelID }) {
            list.append(job)
        }
        return list.sorted { ($0.eventDate ?? .distantPast) > ($1.eventDate ?? .distantPast) }
    }

    var body: some View {
        @Bindable var draft = draft
        @Bindable var pricing = draft.pricing
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(editorTitle)
                    .font(StudioDesign.displayTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Preview", systemImage: "doc.richtext", action: showPreview)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("See the quote PDF without saving")
            }

            clientColumn(pricing: pricing)
            QuotePaymentTermsSection(draft: draft)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InvoiceLinesEditor(draft: pricing, catalog: catalog)
                .frame(maxWidth: .infinity)
            footer
        }
        .padding(24)
        .frame(minWidth: 900, idealWidth: 980)
        .frame(width: 980)
        .fixedSize(horizontal: false, vertical: true)
        .studioActive()
        .focusedSceneValue(\.invoiceEditorActive, true)
        .sheet(item: $jobEditor) { launch in
            JobEditorSheet(contacts: contacts, contact: draft.pricing.contact, job: launch.job) { saved in
                draft.pricing.contact = saved.contact ?? draft.pricing.contact
                draft.pricing.job = saved
            }
        }
        .sheet(item: $contactEditor) { mode in
            ContactEditorSheet(mode: mode) { saved in
                draft.pricing.contact = saved
                draft.pricing.job = nil
            }
        }
        .sheet(item: $previewSession) { session in
            QuotePDFPreviewSheet(quote: session.quote, agreementOnly: false)
        }
    }

    private var editorTitle: String {
        guard draft.isEditing else { return "New quote" }
        let number = draft.titleNumber
        guard !number.isEmpty else { return "Edit quote" }
        return "Edit quote: \(number)"
    }

    private func clientColumn(pricing: InvoiceDraftModel) -> some View {
        @Bindable var pricing = pricing
        return VStack(alignment: .leading, spacing: 12) {
            // Two label columns; colons line up within each.
            HStack(alignment: .top, spacing: 20) {
                StudioLabeledStack {
                    StudioLabeledRow("Client") {
                        ContactPickerField(
                            contacts: contacts,
                            selection: $pricing.contact,
                            label: "Client:",
                            showsLabel: false,
                            onAdd: { contactEditor = .new }
                        )
                    }
                    StudioLabeledRow("Number") {
                        numberField
                    }
                    StudioLabeledRow("Quote date") {
                        DatePicker("Quote date:", selection: $pricing.invoiceDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    StudioLabeledRow("Valid until") {
                        HStack(spacing: 8) {
                            Toggle("Valid until:", isOn: $includeValidUntil)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .onChange(of: includeValidUntil) { _, on in
                                    if on, draft.validUntil == nil {
                                        draft.validUntil = Calendar.current.date(byAdding: .day, value: 30, to: pricing.invoiceDate)
                                    }
                                    if !on { draft.validUntil = nil }
                                }
                            if includeValidUntil {
                                DatePicker(
                                    "Valid until:",
                                    selection: Binding(
                                        get: { draft.validUntil ?? pricing.invoiceDate },
                                        set: { draft.validUntil = $0 }
                                    ),
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                            }
                        }
                    }
                    StudioLabeledRow("Note") {
                        noteField(prompt: "Prints on the quote", text: $pricing.note)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StudioLabeledStack {
                    StudioLabeledRow("Job") {
                        // Row supplies "Job:"; hide the picker's own LabeledContent label.
                        JobMenuPicker(
                            jobs: jobs,
                            selection: pricing.job,
                            onAdd: { presentJobEditor(nil) },
                            onSelect: selectJob,
                            onEdit: presentJobEditor
                        )
                        .labelsHidden()
                    }
                    StudioLabeledRow("Event date") {
                        eventDateField(pricing: pricing)
                    }
                    StudioLabeledRow("Sign-off") {
                        noteField(prompt: "Thank you.", text: $pricing.closing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            InvoiceTaxControls(draft: pricing, schedules: schedules)
        }
        .onChange(of: pricing.contact?.persistentModelID) { _, _ in
            if let job = pricing.job, job.contact?.persistentModelID != pricing.contact?.persistentModelID {
                pricing.job = nil
            }
        }
        .onChange(of: pricing.job?.persistentModelID) { _, _ in
            syncClientFromJob(pricing)
            pricing.fillEmptyNoteFromJob()
            adoptAgreementFromSelectedJob()
            seedPaymentTermsFromJobIfNeeded()
        }
        .onChange(of: pricing.job?.contact?.persistentModelID) { _, _ in
            syncClientFromJob(pricing)
        }
        .onChange(of: pricing.job?.name) { _, _ in
            pricing.fillEmptyNoteFromJob()
        }
    }

    /// Agreement HTML still adopts from the job when empty — editing happens in QuoteAgreementSheet.
    private func selectJob(_ job: Job?) {
        draft.pricing.job = job
        syncClientFromJob()
        adoptAgreementFromSelectedJob()
        seedPaymentTermsFromJobIfNeeded()
    }

    private func seedPaymentTermsFromJobIfNeeded() {
        guard draft.paymentScheduleMode == .none else { return }
        guard let job = draft.pricing.job else { return }
        QuotePaymentSchedule.copySchedule(from: job, into: draft)
    }

    private func syncClientFromJob(_ pricing: InvoiceDraftModel? = nil) {
        let pricing = pricing ?? draft.pricing
        guard let contact = pricing.job?.contact else { return }
        pricing.contact = contact
    }

    private func adoptAgreementFromSelectedJob() {
        _ = draft.adoptAgreement(from: draft.pricing.job, studio: primaryStudio)
    }

    private var primaryStudio: StudioBrand? {
        existing?.studio ?? (try? StudioBrandDirectory.primary(in: modelContext))
    }

    @ViewBuilder
    private func eventDateField(pricing: InvoiceDraftModel) -> some View {
        if pricing.job != nil {
            DatePicker(
                "Event date:",
                selection: Binding(
                    get: { pricing.job?.eventDate ?? pricing.invoiceDate },
                    set: { pricing.job?.eventDate = $0 }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .help("Stored on the job. Fills [Event Date] and payment dates before the event.")
        } else {
            Text("Select a job")
                .foregroundStyle(.secondary)
                .help("Event date comes from the job — pick or add one above.")
        }
    }

    private var numberTaken: Bool {
        draft.isNumberTaken(among: quotes)
    }

    /// Letters and digits allowed. A number another quote already uses blocks saving.
    private var numberField: some View {
        @Bindable var draft = draft
        return VStack(alignment: .leading, spacing: 4) {
            TextField("Assigned when sent", text: $draft.numberText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180, alignment: .leading)
                .onChange(of: draft.numberText) { _, value in
                    let cleaned = QuoteMath.sanitizedNumber(value)
                    if cleaned != value { draft.numberText = cleaned }
                }
            if numberTaken {
                Text("Another quote already uses this number.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func noteField(prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .lineLimit(2, reservesSpace: true)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Save Draft") { save(markSent: false) }
                .disabled(!draft.canSave || numberTaken)
            Button("Save & Mark Sent") { save(markSent: true) }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSave || numberTaken)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func presentJobEditor(_ job: Job?) {
        jobEditor = JobEditorLaunch(job: job)
    }

    private func showPreview() {
        if AgreementAskField.hasUnresolvedAsks(in: draft.agreementHTML) {
            errorMessage = "Fill the Ask fields on the agreement before previewing."
            return
        }
        do {
            previewSession = try draft.makePreview(studio: primaryStudio)
        } catch {
            errorMessage = "Couldn’t open the preview."
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

private struct JobEditorLaunch: Identifiable {
    let id = UUID()
    var job: Job?
}
