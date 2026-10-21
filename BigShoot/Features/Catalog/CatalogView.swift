import SwiftData
import SwiftUI

struct CatalogWorkspace: View {
    @Query(sort: \CatalogItem.timesUsed, order: .reverse) private var items: [CatalogItem]
    @State private var selection: PersistentIdentifier?
    @State private var search = ""
    @State private var showAdd = false

    private var filtered: [CatalogItem] {
        guard !search.isEmpty else { return items }
        return items.filter { $0.name.localizedStandardContains(search) }
    }

    private var selected: CatalogItem? {
        items.first { $0.persistentModelID == selection }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(filtered, selection: $selection) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .lineLimit(2)
                        Text("\(item.timesUsed) billed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(StudioMoney.string(item.defaultPrice))
                        .font(StudioDesign.metric(14))
                        .monospacedDigit()
                }
                .tag(item.persistentModelID)
                .padding(.vertical, 2)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(width: 420)
            .searchable(text: $search, prompt: "Day rate, album, session")
            .navigationTitle("Catalog")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Item", systemImage: "plus") { showAdd = true }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    StudioEmptyState(
                        title: "Catalog is empty",
                        message: "Import line items, or add a name you’ve never billed.",
                        symbol: "list.bullet.rectangle"
                    )
                }
            }
            Divider()
            Group {
                if let selected {
                    CatalogEditor(item: selected)
                } else {
                    StudioEmptyState(
                        title: "Pick a price",
                        message: "Day Rate and the rest of the old invoices live here.",
                        symbol: "tag"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioSceneBackground())
        }
        .sheet(isPresented: $showAdd) {
            CatalogAddSheet()
        }
    }
}

private struct CatalogEditor: View {
    @Environment(\.modelContext) private var modelContext
    var item: CatalogItem
    @State private var price: Decimal = 0
    @State private var detail = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.name)
                .font(StudioDesign.displayTitle)
                .textSelection(.enabled)
            Text("Used \(item.timesUsed) times")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            TextField("Default price", value: $price, format: .number.precision(.fractionLength(2)))
                .font(StudioDesign.metric(28))
            TextField("Detail", text: $detail, axis: .vertical)
                .lineLimit(4...8)
            Button("Save Price") {
                item.defaultPrice = price
                item.detail = detail
                try? modelContext.save()
                saved = true
            }
            .keyboardShortcut(.defaultAction)
            if saved {
                Text("Saved.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(StudioDesign.Spacing.workspace)
        .frame(maxWidth: 560, alignment: .leading)
        .onAppear(perform: load)
        .onChange(of: item.persistentModelID) { _, _ in load() }
    }

    private func load() {
        price = item.defaultPrice
        detail = item.detail
        saved = false
    }
}

private struct CatalogAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var price: Decimal = 0
    @State private var detail = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New catalog item")
                .font(StudioDesign.displayTitle)
            TextField("Name", text: $name)
            TextField("Default price", value: $price, format: .number.precision(.fractionLength(2)))
            TextField("Detail", text: $detail, axis: .vertical)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Add", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = CatalogItem(name: trimmed, defaultPrice: price, detail: detail, timesUsed: 0)
        modelContext.insert(item)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "That name is already in the catalog."
        }
    }
}
