import Charts
import SwiftUI

struct DashboardCollectionChart: View {
    @Binding var window: CollectionWindow
    @Binding var rangeStart: Date
    @Binding var rangeEnd: Date
    @Binding var filter: DashboardLedgerFilter
    var report: CollectionReport
    var invoicedTotal: Decimal

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: showThisPeriod) {
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Collected")
                                .font(.title3)
                                .foregroundStyle(.primary)
                            Text(report.total, format: .currency(code: "USD"))
                                .font(StudioDesign.metric(32))
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .foregroundStyle(StudioDesign.money(for: colorScheme))
                                .contentTransition(reduceMotion ? .identity : .numericText())
                                .animation(reduceMotion ? nil : .snappy, value: report.total)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(window.cashCaption(from: rangeStart, through: rangeEnd))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let caption = DashboardMath.comparisonCaption(
                                current: report.total,
                                prior: report.priorTotal,
                                window: window
                            ) {
                                Text(caption)
                                    .font(.caption)
                                    .foregroundStyle(comparisonTint)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if report.total == 0 {
                                Text("No cash received in this period.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Show invoices paid in this period")
                InvoiceTotalButton(
                    amount: invoicedTotal,
                    selected: showsIssued,
                    hint: invoiceHint,
                    action: showInvoicesThisPeriod
                )
            }
            CollectionPeriodPicker(
                window: $window,
                filter: $filter,
                rangeStart: $rangeStart,
                rangeEnd: $rangeEnd
            )
            chart
                .frame(height: 168)
            Text(selectionCaption)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(activeBucket == nil ? 0 : 1)
                .accessibilityHidden(activeBucket == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioDesign.Spacing.card)
        .studioCard()
        .overlay {
            if let stroke {
                RoundedRectangle(cornerRadius: StudioDesign.Radius.card, style: .continuous)
                    .strokeBorder(stroke.opacity(0.9), lineWidth: 1.5)
            }
        }
    }

    private var showsIssued: Bool {
        filter.billedWindow == window
    }

    private var invoiceHint: String {
        window.billedCaption(from: rangeStart, through: rangeEnd)
    }

    private var stroke: Color? {
        if filter.collectionWindow == window { return StudioDesign.gold }
        if filter.billedWindow == window { return colorScheme == .dark ? .gpBlue : .gpBlueLight }
        return nil
    }

    private func showThisPeriod() {
        filter = .cash(window)
    }

    private func showInvoicesThisPeriod() {
        filter = .issued(window)
    }

    private var showsBarValues: Bool {
        if window == .month { return true }
        return window == .range && report.buckets.count <= 8
    }

    private var chart: some View {
        Chart(report.buckets) { bucket in
            BarMark(
                x: .value("Period", bucket.label),
                y: .value("Collected", DashboardMath.chartDouble(bucket.collected)),
                width: .ratio(0.62)
            )
            .foregroundStyle(barGradient)
            .opacity(barOpacity(for: bucket))
            .cornerRadius(5)
            .accessibilityLabel("\(bucket.label), \(StudioMoney.string(bucket.collected)) collected")
            .annotation(position: .top, spacing: 4) {
                if showsBarValues, bucket.collected > 0 {
                    Text(
                        DashboardMath.chartDouble(bucket.collected),
                        format: .currency(code: "USD").notation(.compactName)
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(StudioDesign.money(for: colorScheme))
                }
            }
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
        .chartXSelection(value: bucketSelection)
        .animation(reduceMotion ? nil : .snappy, value: report)
    }

    private var bucketSelection: Binding<String?> {
        Binding(
            get: { activeBucket?.label },
            set: { label in
                guard let label, let bucket = report.buckets.first(where: { $0.label == label }) else {
                    filter = .cash(window)
                    return
                }
                filter = .cash(window, bucketStart: bucket.start)
            }
        )
    }

    private var activeBucket: CollectionBucket? {
        guard filter.collectionWindow == window, let start = filter.bucketStart else { return nil }
        return report.buckets.first { $0.start == start }
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [StudioDesign.gold, StudioDesign.gold.opacity(0.72)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var yDomain: ClosedRange<Double> {
        let values = report.buckets.map { DashboardMath.chartDouble($0.collected) }
        let peak = values.max() ?? 0
        let floor = min(values.min() ?? 0, 0)
        if peak <= 0, floor >= 0 { return 0...1 }
        return floor...max(peak * 1.22, 1)
    }

    private var selectionCaption: String {
        guard let activeBucket else { return " " }
        return "\(activeBucket.label) · \(StudioMoney.string(activeBucket.collected))"
    }

    private var comparisonTint: Color {
        guard report.priorTotal > 0 else { return .secondary }
        if report.total == report.priorTotal { return .secondary }
        return report.total > report.priorTotal ? StudioDesign.paid : StudioDesign.rose
    }

    private func barOpacity(for bucket: CollectionBucket) -> Double {
        guard let activeBucket else { return 1 }
        return bucket.start == activeBucket.start ? 1 : 0.35
    }
}
