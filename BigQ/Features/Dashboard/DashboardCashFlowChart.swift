import Charts
import SwiftUI

/// Expected open balance by due month. Past-due and undated invoices sit in the current month.
struct DashboardCashFlowChart: View {
    @Binding var filter: DashboardLedgerFilter
    var report: CashFlowReport

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: showThisMonth) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cash Flow")
                        .font(.title3)
                        .foregroundStyle(.primary)
                    Text(displayedAmount, format: .currency(code: "USD"))
                        .font(StudioDesign.metric(32))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(StudioDesign.money(for: colorScheme))
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : .snappy, value: displayedAmount)
                    Text(amountCaption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    forecastNote
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Show invoices expected this month")
            .accessibilityAddTraits(showsThisMonth ? .isSelected : [])
            chart
                .frame(height: 168)
            Text(selectionCaption)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(hoveredMonth == nil && activeMonth == nil ? 0 : 1)
                .accessibilityHidden(hoveredMonth == nil && activeMonth == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioDesign.Spacing.card)
        .studioCard()
        .overlay {
            if filter.isExpected {
                RoundedRectangle(cornerRadius: StudioDesign.Radius.card, style: .continuous)
                    .strokeBorder(flowColor.opacity(0.9), lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private var forecastNote: some View {
        if showsForecastNote {
            VStack(alignment: .leading, spacing: 2) {
                if report.pastDue > 0 {
                    Text("Includes \(StudioMoney.string(report.pastDue)) already past due")
                        .font(.caption)
                        .foregroundStyle(StudioDesign.rose)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(showingCurrentMonth ? 1 : 0)
                        .accessibilityHidden(!showingCurrentMonth)
                } else if report.thisMonth == 0 {
                    Text(report.later > 0 ? "Nothing is due this month." : "Nothing is expected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(showingCurrentMonth ? 1 : 0)
                        .accessibilityHidden(!showingCurrentMonth)
                }
                if report.later > 0, let last = report.months.last?.label {
                    Text("\(StudioMoney.string(report.later)) due after \(last)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var showsForecastNote: Bool {
        report.pastDue > 0 || report.thisMonth == 0 || report.later > 0
    }

    private var chart: some View {
        Chart(report.months) { month in
            AreaMark(
                x: .value("Month", month.label),
                y: .value("Expected", DashboardMath.chartDouble(month.expected))
            )
            .foregroundStyle(areaGradient)
            .interpolationMethod(.linear)
            .accessibilityHidden(true)

            LineMark(
                x: .value("Month", month.label),
                y: .value("Expected", DashboardMath.chartDouble(month.expected))
            )
            .foregroundStyle(flowColor)
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .accessibilityHidden(true)

            PointMark(
                x: .value("Month", month.label),
                y: .value("Expected", DashboardMath.chartDouble(month.expected))
            )
            .foregroundStyle(flowColor)
            .symbolSize(pointSize(for: month))
            .opacity(pointOpacity(for: month))
            .accessibilityLabel("\(month.label), \(StudioMoney.string(month.expected)) expected")
        }
        .chartLegend(.hidden)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.primary.opacity(0.08))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .currency(code: "USD").notation(.compactName))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXSelection(value: monthSelection)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let label = monthLabel(at: location, proxy: proxy, geometry: geometry)
                            if hoveredLabel != label { hoveredLabel = label }
                        case .ended:
                            hoveredLabel = nil
                        }
                    }
                    .onTapGesture { location in
                        guard let label = monthLabel(at: location, proxy: proxy, geometry: geometry),
                              let month = report.months.first(where: { $0.label == label }) else { return }
                        filter = .expected(month.start)
                    }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: report)
        .animation(reduceMotion ? nil : .snappy, value: hoveredLabel)
    }

    private var flowColor: Color {
        colorScheme == .dark ? .gpBlue : .gpBlueLight
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [flowColor.opacity(0.38), flowColor.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var hoveredMonth: CashFlowMonth? {
        guard let hoveredLabel else { return nil }
        return report.months.first { $0.label == hoveredLabel }
    }

    /// The figure under the pointer. With the pointer off the chart, this is the current month.
    private var displayedAmount: Decimal {
        hoveredMonth?.expected ?? report.thisMonth
    }

    private var amountCaption: String {
        guard let hoveredMonth, hoveredMonth.start != report.months.first?.start else {
            return "Expected this month"
        }
        return "Expected in \(hoveredMonth.label)"
    }

    private var showingCurrentMonth: Bool {
        guard let hoveredMonth, let current = report.months.first else { return true }
        return hoveredMonth.start == current.start
    }

    private var emphasizedMonth: CashFlowMonth? {
        hoveredMonth ?? activeMonth
    }

    private var showsThisMonth: Bool {
        guard let start = report.months.first?.start else { return false }
        return filter.expectedMonthStart == start
    }

    private var monthSelection: Binding<String?> {
        Binding(
            get: { activeMonth?.label },
            set: { label in
                guard let label, let month = report.months.first(where: { $0.label == label }) else {
                    filter = .expected(nil)
                    return
                }
                filter = .expected(month.start)
            }
        )
    }

    private var activeMonth: CashFlowMonth? {
        guard let start = filter.expectedMonthStart else { return nil }
        return report.months.first { $0.start == start }
    }

    private var yDomain: ClosedRange<Double> {
        let values = report.months.map { DashboardMath.chartDouble($0.expected) }
        let peak = values.max() ?? 0
        if peak <= 0 { return 0...1 }
        return 0...max(peak * 1.22, 1)
    }

    private var selectionCaption: String {
        if let hoveredMonth {
            return "\(hoveredMonth.label) · \(StudioMoney.string(hoveredMonth.expected))"
        }
        guard let activeMonth else { return " " }
        return "\(activeMonth.label) · \(StudioMoney.string(activeMonth.expected))"
    }

    private func monthLabel(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> String? {
        guard let plotAnchor = proxy.plotFrame else { return nil }
        let frame = geometry[plotAnchor]
        let x = location.x - frame.origin.x
        guard x >= 0, x <= frame.width else { return nil }
        return proxy.value(atX: x, as: String.self)
    }

    private func showThisMonth() {
        guard let start = report.months.first?.start else {
            filter = .expected(nil)
            return
        }
        filter = .expected(start)
    }

    private func pointSize(for month: CashFlowMonth) -> CGFloat {
        guard let emphasizedMonth else { return 48 }
        return month.start == emphasizedMonth.start ? 80 : 28
    }

    private func pointOpacity(for month: CashFlowMonth) -> Double {
        guard let emphasizedMonth else { return 1 }
        return month.start == emphasizedMonth.start ? 1 : 0.35
    }
}
