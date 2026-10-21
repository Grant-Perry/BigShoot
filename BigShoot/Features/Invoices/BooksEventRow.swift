import SwiftUI

struct BooksEventRow: View {
    var event: BooksEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.kind.title)
                    .font(.headline)
                Spacer()
                Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(event.detail)
                .font(.callout)
            Text("\(event.invoiceNumber) · \(event.clientName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
