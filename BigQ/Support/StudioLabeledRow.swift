import SwiftUI

/// Vertical labeled fields whose colons share one trailing edge.
struct StudioLabeledStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            content()
        }
    }
}

/// One labeled row for `StudioLabeledStack`. Always renders a trailing `:`.
struct StudioLabeledRow<Content: View>: View {
    var label: String
    @ViewBuilder var content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    private var titled: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix(":") ? trimmed : trimmed + ":"
    }

    var body: some View {
        GridRow {
            Text(titled)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
                .multilineTextAlignment(.trailing)
            content()
                .gridColumnAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
