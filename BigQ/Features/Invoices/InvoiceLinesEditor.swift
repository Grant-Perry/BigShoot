import SwiftData
import SwiftUI

/// Wide line table. The description keeps the spare width and wraps, so a catalog name stays readable after it is added.
struct InvoiceLinesEditor: View {
    @Bindable var draft: InvoiceDraftModel
    var catalog: [CatalogItem]

    @State private var catalogQuery = ""
    @State private var scrollTarget: UUID?
    @State private var pendingFocus: UUID?
    @FocusState private var catalogFocused: Bool
    @FocusState private var focusedLine: UUID?

    private var showCatalog: Bool {
        catalogFocused || !catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var catalogMatches: [CatalogItem] {
        let query = catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches: [CatalogItem]
        if query.isEmpty {
            matches = catalog.sorted { lhs, rhs in
                if lhs.timesUsed != rhs.timesUsed { return lhs.timesUsed > rhs.timesUsed }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        } else {
            matches = catalog.filter {
                $0.name.localizedStandardContains(query) || $0.detail.localizedStandardContains(query)
            }
        }
        return Array(matches.prefix(12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if showCatalog {
                catalogResults
            }
            lines
            Button("Add a blank line", systemImage: "plus", action: addBlankLine)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(StudioDesign.Spacing.card)
        .paperCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Button("Find Catalog Item") {
                catalogFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Line items")
                .font(.headline)
            Text("\(draft.lines.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("\(draft.lines.count) lines")
            Spacer(minLength: 16)
            catalogField
                .frame(width: 380)
        }
    }

    private var catalogField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Add from catalog", text: $catalogQuery)
                .textFieldStyle(.plain)
                .focused($catalogFocused)
            if !catalogQuery.isEmpty {
                Button("Clear catalog search", systemImage: "xmark.circle.fill") {
                    catalogQuery = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var catalogResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if catalogMatches.isEmpty {
                    Text("Nothing in the catalog matches that.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(catalogMatches.enumerated()), id: \.element.persistentModelID) { index, item in
                        catalogButton(item)
                        if index < catalogMatches.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 240)
    }

    private func catalogButton(_ item: CatalogItem) -> some View {
        Button {
            addCatalogItem(item)
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
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(StudioMoney.string(item.defaultPrice))
                    .font(StudioDesign.metric(14))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(item.name), \(StudioMoney.string(item.defaultPrice))")
    }

    private var lines: some View {
        ScrollViewReader { proxy in
            Group {
                if draft.lines.isEmpty {
                    Text("No lines yet. Search the catalog, or add a blank line.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 4)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        columnHeader
                        Divider()
                            .padding(.top, 4)
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach($draft.lines) { $line in
                                    lineRow($line)
                                        .padding(.vertical, 12)
                                        .id(line.id)
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: scrollTarget) { _, id in
                guard let id else { return }
                Task { @MainActor in
                    proxy.scrollTo(id, anchor: .center)
                    if pendingFocus == id {
                        pendingFocus = nil
                        focusedLine = id
                    }
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Column.gap) {
            Text("Description")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Qty")
                .frame(width: Column.qty, alignment: .trailing)
            Text("Price")
                .frame(width: Column.price, alignment: .trailing)
            Text("Amount")
                .frame(width: Column.amount, alignment: .trailing)
            Text("Tax")
                .frame(width: Column.tax, alignment: .center)
            Color.clear
                .frame(width: Column.remove)
                .accessibilityHidden(true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func lineRow(_ line: Binding<DraftLine>) -> some View {
        let lineID = line.wrappedValue.id
        return HStack(alignment: .top, spacing: Column.gap) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Description", text: line.name, axis: .vertical)
                    .lineLimit(1...4)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($focusedLine, equals: lineID)
                    .accessibilityLabel("Description")
                TextField("Detail", text: line.detail, axis: .vertical)
                    .font(.callout)
                    .lineLimit(1...3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Detail")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField(
                "Qty",
                value: line.quantity,
                format: .number.precision(.fractionLength(0...2))
            )
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: Column.qty)
            .accessibilityLabel("Quantity")

            TextField(
                "Price",
                value: line.unitPrice,
                format: .number.precision(.fractionLength(2))
            )
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: Column.price)
            .accessibilityLabel("Price")

            Text(StudioMoney.string(line.wrappedValue.lineTotal))
                .font(StudioDesign.metric(16))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Column.amount, alignment: .trailing)
                .frame(minHeight: 22)
                .accessibilityLabel("Amount")

            Toggle("Taxable", isOn: line.taxable)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: Column.tax)
                .padding(.top, 4)
                .help("Tax this line")

            Button(role: .destructive) {
                draft.removeLine(id: lineID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .frame(width: Column.remove)
            .padding(.top, 2)
            .help("Remove line")
            .accessibilityLabel("Remove line")
        }
    }

    private func addCatalogItem(_ item: CatalogItem) {
        draft.addCatalogItem(item)
        catalogQuery = ""
        catalogFocused = false
        scrollTarget = draft.lines.last?.id
    }

    private func addBlankLine() {
        catalogFocused = false
        draft.addBlankLine()
        guard let id = draft.lines.last?.id else { return }
        pendingFocus = id
        scrollTarget = id
    }
}

private enum Column {
    static let qty: CGFloat = 72
    static let price: CGFloat = 120
    static let amount: CGFloat = 132
    static let tax: CGFloat = 36
    static let remove: CGFloat = 28
    static let gap: CGFloat = 14
}
