import SwiftData
import SwiftUI

/// Catalog search that floats over the invoice. Adding a row does not resize the line list.
struct InvoiceCatalogPicker: View {
    var catalog: [CatalogItem]
    var onAdd: (CatalogItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var lastAdded = ""
    @FocusState private var searchFocused: Bool

    private var matches: [CatalogItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = trimmed.isEmpty
            ? catalog
            : catalog.filter {
                $0.name.localizedStandardContains(trimmed) || $0.detail.localizedStandardContains(trimmed)
            }
        return pool.sorted { lhs, rhs in
            if lhs.timesUsed != rhs.timesUsed { return lhs.timesUsed > rhs.timesUsed }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search the catalog", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if matches.isEmpty {
                        Text(catalog.isEmpty ? "The catalog is empty." : "Nothing in the catalog matches that.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(Array(matches.enumerated()), id: \.element.persistentModelID) { index, item in
                            catalogRow(item)
                            if index < matches.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(lastAdded.isEmpty ? "Pick a row to add it. This stays open." : "Added \(lastAdded)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 460, height: 320)
        .onAppear {
            Task { @MainActor in
                searchFocused = true
            }
        }
    }

    private func catalogRow(_ item: CatalogItem) -> some View {
        Button {
            lastAdded = item.name
            onAdd(item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudioDesign.gold)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(StudioMoney.string(item.defaultPrice))
                    .font(StudioDesign.metric(14))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(item.name), \(StudioMoney.string(item.defaultPrice))")
    }
}
