import SwiftUI

struct QuoteListRow: View {
    var quote: Quote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(quote.displayNumber)
                    .font(.headline)
                Spacer(minLength: 8)
                QuoteStatusBadge(status: quote.status)
            }
            Text(quote.clientName)
                .foregroundStyle(.secondary)
            HStack {
                Text(StudioDay.string(quote.quoteDate))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(StudioMoney.string(quote.total))
                    .font(.callout.monospacedDigit())
            }
        }
        .padding(.vertical, 4)
    }
}

struct QuoteStatusBadge: View {
    var status: QuoteStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch status {
        case .signed: StudioDesign.paid
        case .sent: StudioDesign.gold
        case .draft, .void: .secondary
        }
    }
}
