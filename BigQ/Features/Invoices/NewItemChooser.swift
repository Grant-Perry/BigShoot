import SwiftUI

enum NewStudioItem: String, CaseIterable, Identifiable {
    case quote
    case invoice
    case job
    case contact
    case catalogItem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quote: "Quote"
        case .invoice: "Invoice"
        case .job: "Job"
        case .contact: "Contact"
        case .catalogItem: "Catalog Item"
        }
    }

    var symbol: String {
        switch self {
        case .quote: "doc.plaintext"
        case .invoice: "doc.text"
        case .job: "camera"
        case .contact: "person.crop.circle.badge.plus"
        case .catalogItem: "tag"
        }
    }

    var help: String {
        switch self {
        case .quote: "Proposal with agreement and payment terms"
        case .invoice: "Bill a client from the books"
        case .job: "Wedding, portrait, or shoot on the calendar"
        case .contact: "Someone in the studio book"
        case .catalogItem: "Price list line you reuse on quotes and invoices"
        }
    }
}

/// Compact picker for ⌘N when you are not already inside an invoice/quote editor.
struct NewItemChooserSheet: View {
    var onChoose: (NewStudioItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New")
                .font(StudioDesign.displayTitle)
            Text("What do you want to create?")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(NewStudioItem.allCases) { item in
                    Button {
                        // Parent dismisses this sheet first, then opens the editor.
                        onChoose(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.title3)
                                .frame(width: 28)
                                .foregroundStyle(StudioDesign.gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(item.help)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(StudioDesign.Surface.paper.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.2))
                    )
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .studioActive()
    }
}

/// ⌘N opens the New chooser. Inside an invoice/quote editor it still adds from the catalog.
struct NewItemCommand: View {
    @FocusedValue(\.invoiceEditorActive) private var invoiceEditorActive

    var body: some View {
        if invoiceEditorActive == true {
            Button("Add from Catalog") {
                NotificationCenter.default.post(name: .bigQAddCatalogItem, object: nil)
            }
            .keyboardShortcut("n")
        } else {
            Button("New…") {
                NotificationCenter.default.post(name: .bigQNewItem, object: nil)
            }
            .keyboardShortcut("n")
        }
    }
}
