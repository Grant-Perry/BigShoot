import SwiftUI

/// Smaller invoice-total control under a cash total. Clicking lists invoices dated in that period.
struct InvoiceTotalButton: View {
    var amount: Decimal
    var selected: Bool
    var hint: String
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(amount, format: .currency(code: "USD"))
                    .font(.subheadline.weight(selected ? .bold : .semibold))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("invoiced")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(invoiceTint)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .help(hint)
        .accessibilityHint(hint)
        .accessibilityLabel("Invoice total")
        .accessibilityValue(Text(amount, format: .currency(code: "USD")))
        .accessibilityInputLabels([Text("Invoice total"), Text("Invoiced")])
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(reduceMotion ? nil : .snappy, value: amount)
        .onHover { hovering = $0 }
        .background {
            if hovering || selected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(invoiceTint.opacity(hovering ? 0.16 : 0.12))
            }
        }
    }

    /// Light cyan on the night scene. The deeper blue stays readable on paper.
    private var invoiceTint: Color {
        colorScheme == .dark ? .gpBlue : .gpBlueLight
    }
}
