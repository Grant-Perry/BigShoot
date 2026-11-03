import SwiftData
import SwiftUI

struct NewQuoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.fullName) private var contacts: [Contact]
    @Query(sort: \CatalogItem.name) private var catalog: [CatalogItem]
    @Query(sort: \TaxSchedule.name) private var schedules: [TaxSchedule]
    @Query(filter: #Predicate<Contract> { $0.isTemplate }, sort: \Contract.title)
    private var templates: [Contract]

    var existing: Quote?
    @State private var draft: QuoteDraftModel
    @State private var errorMessage: String?
    @State private var jobEditor: JobEditorLaunch?
    @State private var contactEditor: ContactEditorMode?
    @State private var previewSession: QuotePreviewSession?
    @State private var previewAgreementOnly = false
    @State private var includeValidUntil: Bool
    @State private var agreementFlush = AgreementEditFlush()
    /// Mount the NSTextView after the sheet chrome is on screen — sync load of a
    /// wedding agreement during presentation beachballs.
    @State private var mountAgreementEditor = false
    @State private var allowAgreementAutofill = false

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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(editorTitle)
                    .font(StudioDesign.displayTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                Button("Preview", systemImage: "doc.richtext", action: showPreview)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("See the quote PDF without saving")
            }
            .padding(.top, 4)
            .padding(.bottom, 16)

            // Top form scrolls on its own. Agreement editor stays outside — nesting
            // NSTextView inside SwiftUI ScrollView beachballs while typing.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    clientColumn(pricing: pricing)
                    QuotePaymentTermsSection(draft: draft)
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 280)

            Group {
                if mountAgreementEditor {
                    QuoteAgreementEditor(
                        title: $draft.agreementTitle,
                        html: $draft.agreementHTML,
                        templates: templates,
                        onApplyTemplate: { template, answers in
                            draft.applyTemplate(template, askAnswers: answers)
                            draft.fillKnownAgreementFields(studio: primaryStudio)
                        },
                        onClear: draft.clearAgreement,
                        onPreview: showContractPreview,
                        flush: agreementFlush,
                        polishHTML: { source in
                            AgreementMerge.resolve(
                                source,
                                with: draft.agreementMergeContext(studio: primaryStudio),
                                skipEmptyValues: true
                            )
                        }
                    )
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading agreement…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .studioCard(cornerRadius: 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            .padding(.top, 12)

            // Don't wrap in another height-capped ScrollView — that clipped Subtotal/Tax/Total.
            // InvoiceLinesEditor already scrolls its own rows and keeps totals below them.
            InvoiceLinesEditor(draft: pricing, catalog: catalog)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            footer
                .padding(.top, 16)
        }
        .padding(24)
        .frame(minWidth: 980, idealWidth: 1040)
        .frame(minHeight: 700, idealHeight: 820, maxHeight: 920)
        .studioActive()
        .focusedSceneValue(\.invoiceEditorActive, true)
        .onAppear {
            // Let the sheet present first, then mount/parse the agreement off that turn.
            Task { @MainActor in
                await Task.yield()
                mountAgreementEditor = true
                await Task.yield()
                allowAgreementAutofill = true
            }
        }
        .onChange(of: draft.paymentScheduleMode) { _, _ in
            guard allowAgreementAutofill else { return }
            agreementFlush.call()
            draft.fillKnownAgreementFields(studio: primaryStudio)
        }
        .onChange(of: draft.paymentTerms) { _, _ in
            guard allowAgreementAutofill else { return }
            agreementFlush.call()
            draft.fillKnownAgreementFields(studio: primaryStudio)
        }
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
            QuotePDFPreviewSheet(quote: session.quote, agreementOnly: previewAgreementOnly)
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
            HStack(alignment: .top, spacing: 20) {
                ContactPickerField(
                    contacts: contacts,
                    selection: $pricing.contact,
                    label: "Client:",
                    onAdd: { contactEditor = .new }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                JobMenuPicker(
                    jobs: jobs,
                    selection: pricing.job,
                    onAdd: { presentJobEditor(nil) },
                    onSelect: selectJob,
                    onEdit: presentJobEditor
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 20) {
                DatePicker("Quote date:", selection: $pricing.invoiceDate, displayedComponents: .date)
                eventDateField(pricing: pricing)
                Toggle("Valid until", isOn: $includeValidUntil)
                    .toggleStyle(.checkbox)
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
                }
                Spacer(minLength: 0)
            }
            InvoiceTaxControls(draft: pricing, schedules: schedules)
            HStack(alignment: .top, spacing: 20) {
                field("Note:", prompt: "Prints on the quote", text: $pricing.note)
                field("Sign-off:", prompt: "Thank you.", text: $pricing.closing)
            }
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

    /// Agreement client fields always follow the job’s contact.
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

    /// `[Event Date]`, payment “days before event,” and the agreement all use the job’s date.
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
            .help("Stored on the job. Fills [Event Date] and payment dates before the event.")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Event date:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Select a job")
                    .foregroundStyle(.secondary)
                    .help("Event date comes from the job — pick or add one above.")
            }
        }
    }

    private func field(_ title: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(prompt, text: text, axis: .vertical)
                .lineLimit(2, reservesSpace: true)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Save Draft") { save(markSent: false) }
                .disabled(!draft.canSave)
            Button("Save & Mark Sent") { save(markSent: true) }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSave)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func presentJobEditor(_ job: Job?) {
        jobEditor = JobEditorLaunch(job: job)
    }

    private func showPreview() {
        openPreview(agreementOnly: false)
    }

    private func showContractPreview() {
        openPreview(agreementOnly: true)
    }

    private func openPreview(agreementOnly: Bool) {
        agreementFlush.call()
        if AgreementAskField.hasUnresolvedAsks(in: draft.agreementHTML) {
            errorMessage = "Fill the Ask fields on the agreement before previewing."
            return
        }
        if agreementOnly,
           draft.agreementTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           draft.agreementHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Add an agreement before previewing the contract."
            return
        }
        do {
            previewAgreementOnly = agreementOnly
            previewSession = try draft.makePreview(studio: primaryStudio)
        } catch {
            errorMessage = "Couldn’t open the preview."
        }
    }

    private func save(markSent: Bool) {
        agreementFlush.call()
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
