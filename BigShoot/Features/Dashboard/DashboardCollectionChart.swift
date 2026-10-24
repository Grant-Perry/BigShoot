import Charts
import SwiftUI

struct DashboardCollectionChart: View {
    @Binding var window: CollectionWindow
    @Binding var rangeStart: Date
    @Binding var rangeEnd: Date
    @Binding var filter: DashboardLedgerFilter
    var report: CollectionReport

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: showThisPeriod) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Collected")
                        .font(.title3)
                        .foregroundStyle(.primary)
                    Text(report.total, format: .currency(code: "USD"))
                        .font(StudioDesign.metric(32))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : .snappy, value: report.total)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Show invoices paid in this period")
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
            if filter.collectionWindow != nil {
                RoundedRectangle(cornerRadius: StudioDesign.Radius.card, style: .continuous)
                    .strokeBorder(StudioDesign.gold.opacity(0.9), lineWidth: 1.5)
            }
        }
    }

    private func showThisPeriod() {
        filter = .cash(window)
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
                    .foregroundStyle(.secondary)
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
