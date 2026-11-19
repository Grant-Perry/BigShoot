import SwiftData
import SwiftUI

struct QuoteEmailsSection: View {
    var quote: Quote
    var onOpen: (QuoteEmail) -> Void
    var onCompose: () -> Void

    @Query(sort: \QuoteEmail.updatedAt, order: .reverse) private var emails: [QuoteEmail]

    private var mine: [QuoteEmail] {
        let key = QuoteMailKey.existing(for: quote)
        guard !key.isEmpty else { return [] }
        return emails.filter { $0.quoteKey == key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Emails", systemImage: "envelope")
                    .font(.headline)
                Spacer(minLength: 8)
                if !mine.isEmpty {
                    Button("Send Quote", systemImage: "square.and.pencil", action: onCompose)
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderless)
                        .help("Write another email for this quote")
                }
            }
            if mine.isEmpty {
                Text("Nothing sent yet. Write a note, pick a template, and send the quote with the pay link.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Send Quote", systemImage: "envelope", action: onCompose)
                    .buttonStyle(.bordered)
                    .help("Email this quote")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(mine) { email in
                        Button {
                            onOpen(email)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(email.subject.isEmpty ? "Untitled" : email.subject)
                                        .foregroundStyle(.primary)
                                    Text(email.statusLine)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help("Open this email")
                        .accessibilityLabel("Open email \(email.subject)")
                    }
                }
                .font(.callout)
            }
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }
}
