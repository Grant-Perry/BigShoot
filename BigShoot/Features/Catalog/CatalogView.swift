import SwiftData
import SwiftUI

struct CatalogWorkspace: View {
    @Query(sort: \CatalogItem.timesUsed, order: .reverse) private var items: [CatalogItem]
    @State private var selection: PersistentIdentifier?
    @State private var search = ""
    @State private var showAdd = false
    @State private var editingItem: CatalogItem?

    private var filtered: [CatalogItem] {
        guard !search.isEmpty else { return items }
        return items.filter { $0.name.localizedStandardContains(search) }
    }

    private var selected: CatalogItem? {
        items.first { $0.persistentModelID == selection }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                StudioColumnSearch(text: $search, prompt: "Day rate, album, session", findLabel: "Find Catalog Item")
                List(filtered, selection: $selection) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .lineLimit(2)
                            Text(item.taxable == true ? "\(item.timesUsed) billed · Taxable" : "\(item.timesUsed) billed")
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
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") {
                            selection = item.persistentModelID
                            editingItem = item
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .overlay {
                    if filtered.isEmpty {
                        StudioEmptyState(
                            title: search.isEmpty ? "Catalog is empty" : "No matches",
                            message: search.isEmpty
                                ? "Import line items, or add a name you’ve never billed."
                                : "Try a different name.",
                            symbol: "list.bullet.rectangle"
                        )
                    }
                }
            }
            .frame(width: 420)
            Divider()
            Group {
                if let selected {
                    CatalogEditor(item: selected) {
                        editingItem = selected
                    }
                } else {
                    StudioEmptyState(
                        title: "Pick a price",
                        message: "Day Rate and the rest of the old invoices live here.",
                        symbol: "tag"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(StudioSceneBackground())
        }
        .navigationTitle("Catalog")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Item", systemImage: "plus") { showAdd = true }
            }
        }
        .sheet(isPresented: $showAdd) {
            CatalogItemSheet()
        }
        .sheet(item: $editingItem) { item in
            CatalogItemSheet(item: item)
        }
    }
}

private struct CatalogEditor: View {
    var item: CatalogItem
    var onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name)
                        .font(StudioDesign.displayTitle)
                        .textSelection(.enabled)
                    Spacer(minLength: 12)
                    Button("Edit", systemImage: "pencil", action: onEdit)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Text("Used \(item.timesUsed) times")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(StudioMoney.string(item.defaultPrice))
                    .font(StudioDesign.metric(28))
                    .monospacedDigit()
                    .textSelection(.enabled)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.taxable == true ? "Taxable" : "Not taxable")
                    .foregroundStyle(.secondary)
                Text("This is the price and tax setting used the next time you add the item. Invoices already written keep their own copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(StudioDesign.Spacing.workspace)
            .padding(.top, StudioDesign.Spacing.section)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .toolbar {
            ToolbarItem {
                Button("Edit", systemImage: "pencil", action: onEdit)
            }
        }
    }
}

private struct CatalogItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var item: CatalogItem?

    @State private var name = ""
    @State private var price: Decimal = 0
    @State private var detail = ""
    @State private var taxable = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { item != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit catalog item" : "New catalog item")
                .font(StudioDesign.displayTitle)
            TextField("Name", text: $name)
                .focused($nameFocused)
            TextField("Default price", value: $price, format: .number.precision(.fractionLength(2)))
            TextField("Detail", text: $detail, axis: .vertical)
                .lineLimit(4...8)
            Toggle("Taxable", isOn: $taxable)
                .toggleStyle(.checkbox)
            Text("This is the price and tax setting used the next time you add the item. Invoices already written keep their own copy.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button(isEditing ? "Save" : "Add", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear(perform: load)
    }

    private func load() {
        guard let item else {
            nameFocused = true
            return
        }
        name = item.name
        price = item.defaultPrice
        detail = item.detail
        taxable = item.taxable ?? false
        nameFocused = true
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item {
            let previousName = item.name
            let previousPrice = item.defaultPrice
            let previousDetail = item.detail
            let previousTaxable = item.taxable
            item.name = trimmed
            item.defaultPrice = price
            item.detail = detail
            item.taxable = taxable
            do {
                try modelContext.save()
                dismiss()
            } catch {
                item.name = previousName
                item.defaultPrice = previousPrice
                item.detail = previousDetail
                item.taxable = previousTaxable
                errorMessage = "That name is already in the catalog."
            }
            return
        }

        let created = CatalogItem(name: trimmed, defaultPrice: price, detail: detail, taxable: taxable, timesUsed: 0)
        modelContext.insert(created)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.delete(created)
            errorMessage = "That name is already in the catalog."
        }
    }
}
