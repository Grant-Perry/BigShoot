import SwiftData
import SwiftUI

/// Compose a draft contract for a job. Client merge fields always come from the job’s contact.
struct JobContractSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Contract> { $0.isTemplate }, sort: \Contract.title)
    private var templates: [Contract]

    var job: Job
    var existing: Contract?

    @State private var title = ""
    @State private var html = ""
    @State private var errorMessage: String?
    @State private var previewItem: ContractPreviewItem?
    @State private var agreementFlush = AgreementEditFlush()

    private var editorTitle: String {
        existing == nil ? "Add contract" : "Edit contract"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(editorTitle)
                    .font(StudioDesign.displayTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Preview", systemImage: "doc.richtext", action: showPreview)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasBody)
                    .help("Preview with the job’s client filled in")
            }
            .padding(.bottom, 16)

            clientBanner
                .padding(.bottom, 16)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }

            // Keep NSTextView out of SwiftUI ScrollView — nested scrolling beachballs on type.
            QuoteAgreementEditor(
                title: $title,
                html: $html,
                templates: templates,
                onApplyTemplate: applyTemplate,
                onClear: clearAgreement,
                onPreview: showPreview,
                flush: agreementFlush,
                mergeSourceLabel: "this job’s client",
                polishHTML: fillKnownFields
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            footer
                .padding(.top, 16)
        }
        .padding(24)
        .frame(minWidth: 900, idealWidth: 980)
        .frame(minHeight: 600, idealHeight: 740, maxHeight: 860)
        .studioActive()
        .onAppear(perform: load)
        .sheet(item: $previewItem) { item in
            ContractReaderSheet(contract: item.contract)
        }
    }

    private var hasBody: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var clientBanner: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Client comes from this job")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let contact = job.contact {
                    Text(contact.displayName)
                        .font(.headline)
                    let details = [contact.email, contact.phone, contact.address]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if !details.isEmpty {
                        Text(details.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("Link a client on the job before the agreement can fill name, email, address, and phone.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if job.contact != nil, hasBody, hasFillableClientTokens {
                Button("Fill Client Fields") {
                    html = fillKnownFields(html)
                }
                .help("Replace blue client and job chips with this job’s contact info")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioDesign.Spacing.card)
        .paperCard()
    }

    private var hasFillableClientTokens: Bool {
        let tokens = [
            "[Client Name]", "[Client First Name]", "[Client Last Name]",
            "[Client Email]", "[Client Phone]", "[Client Company]", "[Client Full Address]",
            "[Primary Client Name]", "[Full Name]", "[First Name]", "[Last Name]",
            "[Email]", "[Phone]", "[Full Address]", "[Primary Contact Name]",
            "[Job Name]", "[Job Type]", "[Event Date]", "[Primary Event Date]",
        ]
        return tokens.contains { html.contains($0) }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Save Draft") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(!hasBody)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func load() {
        if let existing {
            title = existing.title
            html = fillKnownFields(existing.html)
        }
    }

    private func applyTemplate(_ template: Contract, askAnswers: [String: String]) {
        title = template.title
        html = fillKnownFields(AgreementAskField.apply(template.html, answers: askAnswers))
    }

    /// Drop known client / job / studio values into the visible agreement. Empty fields stay as chips.
    private func fillKnownFields(_ source: String) -> String {
        let studio = try? StudioBrandDirectory.primary(in: modelContext)
        return AgreementMerge.resolve(
            source,
            with: AgreementMerge.context(contact: job.contact, job: job, studio: studio),
            skipEmptyValues: true
        )
    }

    private func clearAgreement() {
        title = ""
        html = ""
    }

    private func showPreview() {
        // Defer past NSTextView resignation + session→html sync (avoid AppKit/SwiftUI beachball).
        // Both header Preview and in-editor Preview Contract use this same path.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            agreementFlush.call()
            if AgreementAskField.hasUnresolvedAsks(in: html) {
                errorMessage = "Fill the Ask fields on the agreement before previewing."
                return
            }
            guard hasBody else {
                errorMessage = "Add an agreement before previewing."
                return
            }
            errorMessage = nil
            previewItem = ContractPreviewItem(contract: makeEphemeralPreview())
        }
    }

    private func save() {
        agreementFlush.call()
        if AgreementAskField.hasUnresolvedAsks(in: html) {
            errorMessage = "Fill the Ask fields on the agreement before saving."
            return
        }
        guard hasBody else { return }
        guard job.contact != nil else {
            errorMessage = "Link a client on the job before saving a contract."
            return
        }

        let resolved = resolvedHTML()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let contract: Contract
        if let existing {
            contract = existing
            contract.title = trimmedTitle.isEmpty ? "Agreement" : trimmedTitle
            contract.html = resolved
            contract.eventLabel = StudioDay.string(job.eventDate)
            contract.job = job
            if contract.status.isEmpty || contract.status == "template" {
                contract.status = "draft"
            }
        } else {
            contract = Contract(
                title: trimmedTitle.isEmpty ? "Agreement" : trimmedTitle,
                status: "draft",
                html: resolved,
                eventLabel: StudioDay.string(job.eventDate),
                isTemplate: false,
                job: job
            )
            modelContext.insert(contract)
        }

        ensureSigner(on: contract)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureSigner(on contract: Contract) {
        guard let contact = job.contact else { return }
        if let existing = contract.signatures.first(where: { $0.contact?.persistentModelID == contact.persistentModelID }) {
            existing.displayName = contact.displayName
            return
        }
        if contract.signatures.isEmpty {
            let signature = ContractSignature(
                displayName: contact.displayName,
                completed: false,
                contact: contact
            )
            signature.contract = contract
            modelContext.insert(signature)
        }
    }

    private func resolvedHTML() -> String {
        let studio = try? StudioBrandDirectory.primary(in: modelContext)
        return AgreementMerge.resolve(
            html,
            with: AgreementMerge.context(contact: job.contact, job: job, studio: studio)
        )
    }

    private func makeEphemeralPreview() -> Contract {
        Contract(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Agreement" : title,
            status: "draft",
            html: resolvedHTML(),
            eventLabel: StudioDay.string(job.eventDate),
            job: job
        )
    }
}

private struct ContractPreviewItem: Identifiable {
    let id = UUID()
    let contract: Contract
}
