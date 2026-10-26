import SwiftData
import SwiftUI

/// Line table. Rows stay at the top of the card. Catalog search floats over them.
struct InvoiceLinesEditor: View {
    @Bindable var draft: InvoiceDraftModel
    var catalog: [CatalogItem]

    @State private var showCatalog = false
    @State private var scrollTarget: UUID?
    @State private var pendingFocus: LineField?
    @State private var rowsHeight: CGFloat = 0
    @FocusState private var focusedField: LineField?

    private var rowViewport: CGFloat {
        let measured = rowsHeight > 0 ? rowsHeight : 72
        return min(measured, ListLayout.maxHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        columnHeader
                        Divider()
                            .padding(.top, 4)
                        lineRows
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: RowsHeightKey.self, value: proxy.size.height)
                        }
                    }
                }
                .defaultScrollAnchor(.top)
                .defaultScrollAnchor(.top, for: .sizeChanges)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(rowsHeight <= ListLayout.maxHeight)
                .frame(height: rowViewport)
                .onChange(of: scrollTarget) { _, id in
                    guard let id else { return }
                    let field = pendingFocus
                    Task { @MainActor in
                        proxy.scrollTo(id, anchor: .bottom)
                        pendingFocus = nil
                        if let field {
                            focusedField = field
                        }
                    }
                }
            }
            .onPreferenceChange(RowsHeightKey.self) { height in
                guard abs(height - rowsHeight) > 0.5 else { return }
                rowsHeight = height
            }
            invoiceTotals
        }
        .padding(StudioDesign.Spacing.card)
        .paperCard()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .bigQAddCatalogItem)) { _ in
            showCatalog = true
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Line items")
                .font(.headline)
            Text("\(draft.lines.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("\(draft.lines.count) lines")
            Spacer(minLength: 12)
            Button("Add from catalog", systemImage: "books.vertical") {
                showCatalog = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Search the catalog (⌘N)")
            .popover(isPresented: $showCatalog, arrowEdge: .bottom) {
                InvoiceCatalogPicker(catalog: catalog) { item in
                    addCatalogItem(item)
                }
            }
            Button("Custom line", systemImage: "plus", action: addCustomLine)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("A one-off line that isn’t in the catalog. Parking, a rush fee, anything you type once.")
        }
    }

    private var invoiceTotals: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 5) {
                    amountRow("Subtotal:", draft.subtotal, emphasizes: false)
                    amountRow("Tax:", draft.tax, emphasizes: false)
                    amountRow("Total:", draft.total, emphasizes: true)
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.4))
                    .frame(height: 1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func amountRow(_ label: String, _ amount: Decimal, emphasizes: Bool) -> some View {
        GridRow {
            Text(label)
                .font(emphasizes ? StudioDesign.metric(16) : .body)
            Text(StudioMoney.string(amount))
                .font(emphasizes ? StudioDesign.metric(16) : .body)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(StudioMoney.string(amount))")
    }

    @ViewBuilder
    private var lineRows: some View {
        if draft.lines.isEmpty {
            Text("No lines yet. Add from the catalog, or type a custom line.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } else {
            VStack(spacing: 0) {
                ForEach($draft.lines) { $line in
                    lineRow($line)
                        .padding(.vertical, 8)
                        .id(line.id)
                    Divider()
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
        let editing = isEditing(lineID)
        return HStack(alignment: .top, spacing: Column.gap) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Description", text: line.name, axis: .vertical)
                    .lineLimit(editing ? 1...4 : 1...1)
                    .focused($focusedField, equals: .name(lineID))
                    .accessibilityLabel("Description")
                if editing || !line.wrappedValue.detail.isEmpty {
                    TextField("Detail", text: line.detail, axis: .vertical)
                        .font(.callout)
                        .lineLimit(editing ? 1...3 : 1...1)
                        .focused($focusedField, equals: .detail(lineID))
                        .accessibilityLabel("Detail")
                }
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

            ExpressionPriceField(
                value: line.unitPrice,
                prompt: "Price",
                focus: $focusedField,
                tag: .price(lineID)
            )
            .frame(width: Column.price)

            Text(StudioMoney.string(line.wrappedValue.lineTotal))
                .font(StudioDesign.metric(16))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Column.amount, alignment: .trailing)
                .frame(minHeight: 22)
                .accessibilityLabel("Amount")

            Toggle("Taxable", isOn: lineTax(line))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: Column.tax)
                .padding(.top, 4)
                .help("Tax this line")

            Button("Remove line", systemImage: "minus.circle", role: .destructive) {
                draft.removeLine(id: lineID)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: Column.remove)
            .padding(.top, 2)
            .help("Remove line")
        }
    }

    /// Checking a line's tax box turns on Charge Tax so a rate can be chosen.
    private func lineTax(_ line: Binding<DraftLine>) -> Binding<Bool> {
        Binding(
            get: { line.wrappedValue.taxable },
            set: { isOn in
                var updated = line.wrappedValue
                updated.taxable = isOn
                line.wrappedValue = updated
                if isOn {
                    draft.invoiceTaxable = true
                }
            }
        )
    }

    private func isEditing(_ id: UUID) -> Bool {
        switch focusedField {
        case .name(let lineID), .detail(let lineID):
            lineID == id
        default:
            false
        }
    }

    private func addCatalogItem(_ item: CatalogItem) {
        draft.addCatalogItem(item)
        showCatalog = false
        guard let id = draft.lines.last?.id else { return }
        pendingFocus = .price(id)
        scrollTarget = id
    }

    private func addCustomLine() {
        showCatalog = false
        draft.addBlankLine()
        guard let id = draft.lines.last?.id else { return }
        pendingFocus = .name(id)
        scrollTarget = id
    }
}

private enum LineField: Hashable {
    case name(UUID)
    case detail(UUID)
    case price(UUID)
}

private struct RowsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum ListLayout {
    static let maxHeight: CGFloat = 440
}

private enum Column {
    static let qty: CGFloat = 72
    static let price: CGFloat = 120
    static let amount: CGFloat = 132
    static let tax: CGFloat = 36
    static let remove: CGFloat = 28
    static let gap: CGFloat = 14
}
