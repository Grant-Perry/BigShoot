import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct QuoteDetailView: View {
    var quote: Quote
    var onPreview: () -> Void
    var onPreviewContract: () -> Void = {}
    var onSend: () -> Void
    var onEdit: () -> Void
    var onEditAgreement: () -> Void = {}
    var onMarkSigned: () -> Void
    var onOpenInvoice: (PersistentIdentifier) -> Void
    var onDelete: () -> Void

    @State private var isAgreementExpanded = false
    /// Token for the HTML we expanded. When Save writes new HTML, the token
    /// mismatches and the heavy `AgreementDocumentView` unmounts instead of re-parsing.
    @State private var expandedAgreementToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                titleBlock

                detailsCard

                if quote.paymentScheduleMode != .none, !quote.paymentTerms.isEmpty {
                    paymentTermsCard
                }

                if quote.hasAgreement {
                    agreementCard
                } else if quote.canEdit {
                    addAgreementCard
                }

                linesCard

                if !quote.note.isEmpty || !quote.closing.isEmpty {
                    notesCard
                }
            }
            .padding(StudioDesign.Spacing.card)
            .frame(maxWidth: 760, alignment: .leading)
            .studioCard()
            .padding(StudioDesign.Spacing.workspace)
        }
        .toolbar {
            if quote.canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit", systemImage: "pencil", action: onEdit)
                }
                ToolbarItem {
                    if quote.hasAgreement {
                        Button("Edit Agreement", systemImage: "text.document", action: editAgreement)
                            .help("Edit contract language on this quote")
                    } else {
                        Button("Add Agreement", systemImage: "doc.badge.plus", action: editAgreement)
                            .help("Attach an agreement to this quote")
                    }
                }
            }
            ToolbarItem {
                Button("Preview PDF", systemImage: "doc.richtext", action: onPreview)
            }
            if quote.hasAgreement {
                ToolbarItem {
                    Button("Preview Contract", systemImage: "signature", action: onPreviewContract)
                        .help("Agreement only, with variables filled in")
                }
            }
            if quote.canSend {
                ToolbarItem {
                    Button("Email Quote", systemImage: "envelope", action: onSend)
                }
            }
            if quote.canMarkSigned {
                ToolbarItem {
                    Button("Mark Signed", systemImage: "checkmark.seal", action: onMarkSigned)
                        .help("Convert this quote into an invoice")
                }
            }
            ToolbarItem {
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(quote.displayNumber)
                    .font(StudioDesign.displayTitle)
                QuoteStatusBadge(status: quote.status)
                Spacer(minLength: 12)
                Text(StudioMoney.string(quote.total))
                    .font(.title2.monospacedDigit())
            }
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        [quote.clientName, quote.job?.displayName]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != "—" }
            .joined(separator: " · ")
    }

    // MARK: - Details

    private var detailsCard: some View {
        StudioLabeledStack {
            StudioLabeledRow("Client") {
                Text(quote.clientName)
                    .textSelection(.enabled)
            }
            if let email = quote.contact?.email, !email.isEmpty {
                StudioLabeledRow("Email") {
                    Text(email)
                        .textSelection(.enabled)
                }
            }
            StudioLabeledRow("Quote date") {
                Text(StudioDay.string(quote.quoteDate))
            }
            if let eventDate = quote.job?.eventDate {
                StudioLabeledRow("Event date") {
                    Text(StudioDay.string(eventDate))
                }
            }
            if let validUntil = quote.validUntil {
                StudioLabeledRow("Valid until") {
                    Text(StudioDay.string(validUntil))
                }
            }
            if let job = quote.job {
                StudioLabeledRow("Job") {
                    Text(job.displayName)
                        .textSelection(.enabled)
                }
            }
            if let signedAt = quote.signedAt {
                StudioLabeledRow("Signed") {
                    Text(StudioStamp.string(signedAt))
                }
            }
            if let invoice = quote.convertedInvoice {
                StudioLabeledRow("Invoice") {
                    Button {
                        onOpenInvoice(invoice.persistentModelID)
                    } label: {
                        Label(invoice.displayNumber, systemImage: "doc.text")
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    // MARK: - Payment terms

    private var paymentTermsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Payment terms", systemImage: "calendar.badge.clock")
                .font(.headline)
            Text(quote.paymentScheduleMode.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(quote.sortedPaymentTerms) { term in
                Text(
                    QuotePaymentSchedule.summaryLine(
                        DraftPaymentTerm(
                            title: term.title,
                            amountMode: term.amountMode,
                            percent: term.percent,
                            fixedAmount: term.fixedAmount,
                            dueMode: term.dueMode,
                            daysBeforeEvent: term.daysBeforeEvent,
                            fixedDueDate: term.fixedDueDate ?? .now,
                            amount: term.amount
                        )
                    )
                )
                .font(.callout)
            }
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    // MARK: - Agreement

    private var agreementContentToken: Int {
        var hasher = Hasher()
        hasher.combine(quote.agreementTitle)
        hasher.combine(quote.agreementHTML.count)
        hasher.combine(quote.agreementHTML.prefix(48))
        hasher.combine(quote.agreementHTML.suffix(48))
        return hasher.finalize()
    }

    private var isShowingAgreementBody: Bool {
        isAgreementExpanded && expandedAgreementToken == agreementContentToken
    }

    private func editAgreement() {
        isAgreementExpanded = false
        onEditAgreement()
    }

    private var agreementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        if isShowingAgreementBody {
                            isAgreementExpanded = false
                        } else {
                            expandedAgreementToken = agreementContentToken
                            isAgreementExpanded = true
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label("Agreement", systemImage: "signature")
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isShowingAgreementBody ? 90 : 0))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Agreement")
                .accessibilityValue(isShowingAgreementBody ? "Expanded" : "Collapsed")
                .accessibilityHint(isShowingAgreementBody ? "Collapse agreement" : "Expand agreement")

                Spacer(minLength: 8)

                if quote.canEdit {
                    Button("Edit", systemImage: "pencil", action: editAgreement)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Edit this quote’s agreement")
                }
            }

            if isShowingAgreementBody {
                AgreementDocumentView(
                    html: resolvedAgreement,
                    agreementTitle: quote.agreementTitle.isEmpty ? "Untitled agreement" : quote.agreementTitle,
                    style: .ambient
                )
                .font(.callout)
            }
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var addAgreementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Agreement", systemImage: "signature")
                .font(.headline)
            Text("Attach contract language for the client to sign with this quote.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add agreement", systemImage: "signature", action: onEditAgreement)
                .buttonStyle(.bordered)
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
    }

    // MARK: - Line items

    private var linesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Line items", systemImage: "list.bullet.rectangle")
                .font(.headline)
            ForEach(quote.sortedLines) { line in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                        if !line.detail.isEmpty {
                            Text(line.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(StudioMoney.string(line.lineTotal))
                        .monospacedDigit()
                }
            }
            Divider()
            totalsRow("Tax", quote.tax)
            if quote.discount > 0 { totalsRow("Discount", -quote.discount) }
            if quote.shipping > 0 { totalsRow("Shipping", quote.shipping) }
            totalsRow("Total", quote.total, emphasize: true)
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    // MARK: - Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
            if !quote.note.isEmpty {
                Text(quote.note)
            }
            if !quote.closing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(quote.closing)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    // MARK: - Helpers

    private var resolvedAgreement: String {
        AgreementMerge.resolve(
            quote.agreementHTML,
            with: AgreementMerge.context(
                contact: quote.contact,
                job: quote.job,
                studio: quote.studio,
                quote: quote
            )
        )
    }

    private func totalsRow(_ title: String, _ amount: Decimal, emphasize: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(emphasize ? .primary : .secondary)
            Spacer()
            Text(StudioMoney.string(amount))
                .monospacedDigit()
                .fontWeight(emphasize ? .semibold : .regular)
        }
    }
}
