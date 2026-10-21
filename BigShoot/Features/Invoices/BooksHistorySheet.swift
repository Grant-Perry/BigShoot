import SwiftData
import SwiftUI

struct BooksHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BooksEvent.occurredAt, order: .reverse) private var events: [BooksEvent]

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    ContentUnavailableView {
                        Label("No audit trail yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Payments, edits, and deletions made in BigShoot are recorded here. The ShootQ import did not include a change history.")
                    }
                } else {
                    List(events) { event in
                        BooksEventRow(event: event)
                    }
                }
            }
            .navigationTitle("Audit trail")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }
}
