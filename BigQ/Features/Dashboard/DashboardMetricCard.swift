import SwiftUI

struct DashboardMetricCard: View {
    var title: String
    var value: String
    var caption: String
    var symbol: String
    var emphasis: Color?
    var hint: String
    var action: () -> Void
    var invoiced: Decimal?
    var invoicedHint: String?
    var invoicedSelected: Bool = false
    var invoicedAction: (() -> Void)? = nil
    var valueColor: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 8) {
                    titleRow
                    valueText
                    captionText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(hint)
            .accessibilityLabel("\(title), \(value), \(caption)")
            .accessibilityHint(hint)
            .accessibilityAddTraits(primarySelected ? .isSelected : [])

            if let invoiced, let invoicedAction {
                InvoiceTotalButton(
                    amount: invoiced,
                    selected: invoicedSelected,
                    hint: invoicedHint ?? "Invoices dated in this period",
                    action: invoicedAction
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioDesign.Spacing.card)
        .studioCard()
        .studioActive(emphasis != nil, color: emphasis ?? StudioDesign.gold)
    }

    private var primarySelected: Bool {
        emphasis != nil && !invoicedSelected
    }

    private var titleRow: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var valueText: some View {
        Text(value)
            .font(StudioDesign.metric(30))
            .monospacedDigit()
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .foregroundStyle(valueColor ?? StudioDesign.money(for: colorScheme))
    }

    private var captionText: some View {
        Text(caption)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}
