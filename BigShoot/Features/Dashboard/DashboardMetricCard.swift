import SwiftUI

struct DashboardMetricCard: View {
    var title: String
    var value: String
    var caption: String
    var symbol: String
    var emphasis: Color?
    var hint: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: symbol)
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text(value)
                    .font(StudioDesign.metric(30))
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioDesign.Spacing.card)
            .studioCard()
            .overlay {
                if let emphasis {
                    RoundedRectangle(cornerRadius: StudioDesign.Radius.card, style: .continuous)
                        .strokeBorder(emphasis.opacity(0.9), lineWidth: 1.5)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .help(hint)
        .accessibilityHint(hint)
        .accessibilityAddTraits(emphasis == nil ? AccessibilityTraits() : .isSelected)
    }
}
