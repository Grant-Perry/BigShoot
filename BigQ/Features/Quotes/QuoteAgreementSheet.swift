import SwiftData
import SwiftUI

/// Agreement-only editor for a saved quote — pricing and line items stay in `NewQuoteSheet`.
struct QuoteAgreementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Contract> { $0.isTemplate }, sort: \Contract.title)
    private var templates: [Contract]

    var quote: Quote

    @State private var draft = QuoteDraftModel()
    @State private var errorMessage: String?
    @State private var previewSession: QuotePreviewSession?
    @State private var agreementFlush = AgreementEditFlush()
    @State private var editorMounted = false
    @State private var isSaving = false

    var body: some View {
        @Bindable var draft = draft
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(headerTitle)
                    .font(StudioDesign.displayTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Always enabled: hasBody reads draft, which lags typing. showPreview
                // flushes the editor and checks for an empty agreement itself.
                Button("Preview", systemImage: "doc.richtext", action: showPreview)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Preview the agreement with this quote’s variables filled in")
            }
            .padding(.bottom, 16)

            quoteBanner
                .padding(.bottom, 16)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }

            Group {
                if editorMounted {
                    QuoteAgreementEditor(
                        title: $draft.agreementTitle,
                        html: $draft.agreementHTML,
                        templates: templates,
                        onApplyTemplate: applyTemplate,
                        onClear: { draft.clearAgreement() },
                        onPreview: showPreview,
                        flush: agreementFlush,
                        mergeSourceLabel: "the quote",
                        polishHTML: fillKnownFields
                    )
                } else {
                    // Empty placeholder while Save guts/unmounts — ProgressView felt like a hang.
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            footer
                .padding(.top, 16)
        }
        .padding(24)
        .frame(minWidth: 900, idealWidth: 980)
        .frame(minHeight: 600, idealHeight: 740, maxHeight: 860)
        .studioActive()
        .onAppear(perform: prepare)
        .sheet(item: $previewSession) { session in
            QuotePDFPreviewSheet(quote: session.quote, agreementOnly: true)
        }
    }

    private var headerTitle: String {
        let number = quote.displayNumber
        return number.isEmpty ? "Quote agreement" : "Quote agreement: \(number)"
    }

    private var hasBody: Bool {
        !draft.agreementTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.agreementHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primaryStudio: StudioBrand? {
        quote.studio ?? (try? StudioBrandDirectory.primary(in: modelContext))
    }

    private var quoteBanner: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Client, job, and quote number fill blue fields")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(quote.displayNumber)
                    .font(.headline)
                if let contact = quote.contact {
                    Text(contact.displayName)
                        .font(.subheadline.weight(.medium))
                    let details = [contact.email, contact.phone, contact.address]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if !details.isEmpty {
                        Text(details.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("Link a client on the quote so name, email, address, and phone can merge.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let job = quote.job {
                    Text(job.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if quote.contact != nil, hasBody, hasFillableClientTokens {
                    Button("Fill Client Fields") {
                        // Pull what's in the editor first — typing never reaches draft until
                        // blur, so filling from draft alone would reload stale text over it.
                        agreementFlush.call()
                        draft.agreementHTML = fillKnownFields(draft.agreementHTML)
                    }
                    .help("Replace blue client and job chips with this quote’s contact info")
                }
                if canAdoptJobAgreement {
                    Button("Use job agreement") {
                        _ = draft.adoptAgreement(from: quote.job, studio: primaryStudio)
                    }
                    .help("Copy the agreement from the linked job")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioDesign.Spacing.card)
        .paperCard()
    }

    private var canAdoptJobAgreement: Bool {
        guard !hasBody, let job = quote.job else { return false }
        return ContractLinks.preferredAgreement(for: job) != nil
    }

    private var hasFillableClientTokens: Bool {
        let tokens = [
            "[Client Name]", "[Client First Name]", "[Client Last Name]",
            "[Client Email]", "[Client Phone]", "[Client Company]", "[Client Full Address]",
            "[Primary Client Name]", "[Full Name]", "[First Name]", "[Last Name]",
            "[Email]", "[Phone]", "[Full Address]", "[Primary Contact Name]",
            "[Job Name]", "[Job Type]", "[Event Date]", "[Primary Event Date]",
        ]
        return tokens.contains { draft.agreementHTML.contains($0) }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) {
                agreementFlush.gutEditor()
                dismiss()
            }
                .disabled(isSaving)
                // Don't steal first responder — resigning a wedding NSTextView beachballs.
                .focusable(false)
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                // Not gated on hasBody — draft lags typing. save() checks the pulled text.
                .disabled(isSaving)
                .keyboardShortcut(.defaultAction)
                .focusable(false)
        }
    }

    private func prepare() {
        draft.load(quote)
        draft.fillKnownAgreementFields(studio: primaryStudio)
        editorMounted = false
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(80))
            editorMounted = true
        }
    }

    private func applyTemplate(_ template: Contract, askAnswers: [String: String]) {
        draft.applyTemplate(template, askAnswers: askAnswers)
        draft.agreementHTML = fillKnownFields(draft.agreementHTML)
    }

    private func fillKnownFields(_ source: String) -> String {
        AgreementMerge.resolve(
            source,
            with: AgreementMerge.context(
                contact: quote.contact,
                job: quote.job,
                studio: primaryStudio,
                quote: quote
            ),
            skipEmptyValues: true
        )
    }

    private func showPreview() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            agreementFlush.call()
            if AgreementAskField.hasUnresolvedAsks(in: draft.agreementHTML) {
                errorMessage = "Fill the Ask fields on the agreement before previewing."
                return
            }
            guard hasBody else {
                errorMessage = "Add an agreement before previewing."
                return
            }
            errorMessage = nil
            do {
                previewSession = try draft.makePreview(studio: primaryStudio)
            } catch {
                errorMessage = "Couldn’t open the preview."
                DebugPrint(mode: .error, "Quote agreement preview failed: \(error.localizedDescription)")
            }
        }
    }

    private func save() {
        guard !isSaving else { return }

        // Sync, before any @State write that would rebuild with the editor still live:
        // 1) stop blur publish  2) cheap raw pull  3) gut attributed string + undo
        // 4) unmount. Do NOT write the live Quote until AFTER dismiss — that was
        // rebuilding AgreementDocumentView behind the sheet (spinner → beachball).
        agreementFlush.disarmPublishing()
        let titleSnapshot = draft.agreementTitle
        let raw = agreementFlush.pullRawPlainText()
        agreementFlush.gutEditor()
        agreementFlush.run = {}
        agreementFlush.pull = { "" }
        agreementFlush.pullRaw = { "" }
        agreementFlush.disarm = {}
        agreementFlush.gut = {}
        editorMounted = false
        isSaving = true

        let editingID = quote.persistentModelID
        let mergeContext = draft.agreementMergeContext(studio: quote.studio)

        Task { @MainActor in
            await Task.yield()

            let normalized = AgreementFieldTable.normalizedHTML(
                from: raw,
                agreementTitle: titleSnapshot
            )
            if AgreementAskField.hasUnresolvedAsks(in: normalized) {
                draft.agreementHTML = normalized
                errorMessage = "Fill the Ask fields on the agreement before saving."
                isSaving = false
                editorMounted = true
                return
            }
            let bodyOK = !titleSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard bodyOK else {
                draft.agreementHTML = normalized
                errorMessage = "Add an agreement before saving."
                isSaving = false
                editorMounted = true
                return
            }

            let resolved = AgreementMerge.resolve(
                normalized,
                with: mergeContext,
                skipEmptyValues: false
            )
            let trimmedTitle = titleSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)

            dismiss()
            await Task.yield()

            guard let saved = modelContext.model(for: editingID) as? Quote else { return }
            saved.agreementTitle = trimmedTitle
            saved.agreementHTML = resolved
            do {
                try modelContext.save()
            } catch {
                DebugPrint(mode: .error, "Quote agreement save failed: \(error.localizedDescription)")
            }
        }
    }
}
