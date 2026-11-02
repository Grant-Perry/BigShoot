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
    @State private var draft = QuoteDraftModel()
    @State private var errorMessage: String?
    @State private var jobEditor: JobEditorLaunch?
    @State private var contactEditor: ContactEditorMode?
    @State private var previewSession: QuotePreviewSession?
    @State private var includeValidUntil = false

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
            HStack {
                Text(editorTitle)
                    .font(StudioDesign.displayTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Preview", systemImage: "doc.richtext", action: showPreview)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("See the quote PDF without saving")
            }
            clientColumn(pricing: pricing)
            QuoteAgreementEditor(
                title: $draft.agreementTitle,
                html: $draft.agreementHTML,
                templates: templates,
                onApplyTemplate: draft.applyTemplate,
                onClear: draft.clearAgreement
            )
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
        .frame(width: 860)
        .fixedSize(horizontal: false, vertical: true)
        .studioActive()
        .focusedSceneValue(\.invoiceEditorActive, true)
        .onAppear {
            if let existing {
                draft.load(existing)
                includeValidUntil = existing.validUntil != nil
            }
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
            QuotePDFPreviewSheet(quote: session.quote)
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
                    onSelect: { pricing.job = $0 },
                    onEdit: presentJobEditor
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 20) {
                DatePicker("Quote date:", selection: $pricing.invoiceDate, displayedComponents: .date)
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
            pricing.fillEmptyNoteFromJob()
        }
        .onChange(of: pricing.job?.name) { _, _ in
            pricing.fillEmptyNoteFromJob()
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
        let studio = existing?.studio ?? (try? StudioBrandDirectory.primary(in: modelContext))
        do {
            previewSession = try draft.makePreview(studio: studio)
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
