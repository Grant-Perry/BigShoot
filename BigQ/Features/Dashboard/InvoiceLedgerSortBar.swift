import SwiftUI

/// Sort key and direction for the dashboard invoice list.
struct InvoiceLedgerSortBar: View {
    @Binding var sort: InvoiceLedgerSort
    @Binding var ascending: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("Sort:")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Picker("Sort by", selection: sortSelection) {
                ForEach(InvoiceLedgerSort.allCases) { key in
                    Text(key.title)
                        .accessibilityLabel(key.accessibilityTitle)
                        .tag(key)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Sort by")

            Button(
                ascending ? "Asc" : "Desc",
                systemImage: ascending ? "arrow.up" : "arrow.down",
                action: toggleAscending
            )
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(directionPhrase)
            .accessibilityLabel("Sort direction")
            .accessibilityValue(directionPhrase)
            .accessibilityInputLabels([
                "Sort direction",
                "Ascending",
                "Descending",
                directionPhrase
            ])
        }
    }

    private var directionPhrase: String {
        sort.directionPhrase(ascending: ascending)
    }

    private var sortSelection: Binding<InvoiceLedgerSort> {
        Binding(
            get: { sort },
            set: { newValue in
                guard newValue != sort else { return }
                sort = newValue
                ascending = newValue.defaultAscending
            }
        )
    }

    private func toggleAscending() {
        ascending.toggle()
    }
}
