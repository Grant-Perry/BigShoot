import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct QuoteDetailView: View {
    var quote: Quote
    var onPreview: () -> Void
    var onSend: () -> Void
    var onEdit: () -> Void
    var onMarkSigned: () -> Void
    var onOpenInvoice: (PersistentIdentifier) -> Void
    var onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if quote.hasAgreement { agreement }
                lines
                if !quote.note.isEmpty || !quote.closing.isEmpty {
                    notes
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .toolbar {
            if quote.canEdit {
                ToolbarItem {
                    Button("Edit", systemImage: "pencil", action: onEdit)
                }
            }
            ToolbarItem {
                Button("Preview PDF", systemImage: "doc.richtext", action: onPreview)
            }
            if quote.canSend {
                ToolbarItem {
                    Button("Email Quote", systemImage: "envelope", action: onSend)
                }
            }
            if quote.canMarkSigned {
                ToolbarItem {
                    Button("Mark Signed", systemImage: "signature", action: onMarkSigned)
                        .help("Convert this quote into an invoice")
                }
            }
            ToolbarItem {
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(quote.displayNumber)
                    .font(StudioDesign.displayTitle)
                QuoteStatusBadge(status: quote.status)
                Spacer()
                Text(StudioMoney.string(quote.total))
                    .font(.title2.monospacedDigit())
            }
            Text(quote.clientName)
                .font(.title3)
            if let email = quote.contact?.email, !email.isEmpty {
                Text(email).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                labeled("Quote date", StudioDay.string(quote.quoteDate))
                if let validUntil = quote.validUntil {
                    labeled("Valid until", StudioDay.string(validUntil))
                }
                if let job = quote.job {
                    labeled("Job", job.displayName)
                }
            }
            if let invoice = quote.convertedInvoice {
                Button {
                    onOpenInvoice(invoice.persistentModelID)
                } label: {
                    Label("Opened as invoice \(invoice.displayNumber)", systemImage: "doc.text")
                }
                .buttonStyle(.link)
            }
            if let signedAt = quote.signedAt {
                labeled("Signed", StudioStamp.string(signedAt))
            }
        }
        .studioCard()
    }

    private var agreement: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Agreement", systemImage: "signature")
                .font(.headline)
            Text(quote.agreementTitle.isEmpty ? "Untitled agreement" : quote.agreementTitle)
            Text(ContractDocument.plain(quote.agreementHTML))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(8)
        }
        .studioCard()
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Line items")
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
        .studioCard()
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !quote.note.isEmpty {
                Text(quote.note)
            }
            if !quote.closing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(quote.closing)
                    .foregroundStyle(.secondary)
            }
        }
        .studioCard()
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
        }
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
