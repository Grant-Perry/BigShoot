import Charts
import SwiftUI

struct DashboardOpenBook: View {
    var split: OpenBookSplit
    @Binding var filter: DashboardLedgerFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { filter = .open }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Still out")
                        .font(.title3)
                        .foregroundStyle(.primary)
                    Text(split.total, format: .currency(code: "USD"))
                        .font(StudioDesign.metric(28))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text("Open balance")
                        .font(.subheadline)
                        .foregroundStyle(filter == .open ? StudioDesign.gold : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Show open invoices")
            if split.total == 0 {
                Text("Nothing is open.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    donut
                    legend
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioDesign.Spacing.card)
        .studioCard()
        .overlay {
            if filter == .open || filter == .notYetDue || filter == .overdue {
                RoundedRectangle(cornerRadius: StudioDesign.Radius.card, style: .continuous)
                    .strokeBorder(ringColor.opacity(0.9), lineWidth: 1.5)
            }
        }
    }

    private var donut: some View {
        ZStack {
            Chart(split.populatedKinds) { kind in
                SectorMark(
                    angle: .value("Amount", DashboardMath.chartDouble(split.amount(for: kind))),
                    innerRadius: .ratio(0.66),
                    angularInset: split.populatedKinds.count > 1 ? 1.8 : 0
                )
                .cornerRadius(3)
                .foregroundStyle(color(for: kind))
            }
            .chartLegend(.hidden)
            VStack(spacing: 0) {
                Text(overduePercent)
                    .font(StudioDesign.metric(18))
                    .monospacedDigit()
                    .foregroundStyle(split.overdue > 0 ? StudioDesign.rose : StudioDesign.paid)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("overdue")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 68)
            .accessibilityHidden(true)
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open balance")
        .accessibilityValue(summary)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(OpenBookSplit.Kind.allCases) { kind in
                Button(action: { filter = filter(for: kind) }) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: kind.symbol)
                                .font(.caption)
                                .foregroundStyle(color(for: kind))
                                .frame(width: 14)
                                .accessibilityHidden(true)
                            Text(kind.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(shareText(for: kind))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(StudioMoney.string(split.amount(for: kind)))
                            .font(StudioDesign.metric(15))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(selectionFill(for: kind), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(hint(for: kind))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ringColor: Color {
        filter == .overdue ? StudioDesign.rose : StudioDesign.gold
    }

    private func filter(for kind: OpenBookSplit.Kind) -> DashboardLedgerFilter {
        switch kind {
        case .current: .notYetDue
        case .overdue: .overdue
        }
    }

    private func isSelected(_ kind: OpenBookSplit.Kind) -> Bool {
        filter == filter(for: kind)
    }

    private func selectionFill(for kind: OpenBookSplit.Kind) -> Color {
        isSelected(kind) ? color(for: kind).opacity(0.18) : .clear
    }

    private func hint(for kind: OpenBookSplit.Kind) -> String {
        switch kind {
        case .current: "Show invoices that are not yet due"
        case .overdue: "Show overdue invoices"
        }
    }

    private var overduePercent: String {
        guard split.total > 0 else { return "0%" }
        let ratio = DashboardMath.chartDouble(split.overdue / split.total)
        return ratio.formatted(.percent.precision(.fractionLength(0)))
    }

    private var summary: String {
        "\(overduePercent) overdue, \(StudioMoney.string(split.overdue)) of \(StudioMoney.string(split.total))"
    }

    private func shareText(for kind: OpenBookSplit.Kind) -> String {
        guard split.total > 0 else { return "" }
        let ratio = DashboardMath.chartDouble(split.amount(for: kind) / split.total)
        return ratio.formatted(.percent.precision(.fractionLength(0)))
    }

    private func color(for kind: OpenBookSplit.Kind) -> Color {
        switch kind {
        case .current: StudioDesign.gold
        case .overdue: StudioDesign.rose
        }
    }
}
