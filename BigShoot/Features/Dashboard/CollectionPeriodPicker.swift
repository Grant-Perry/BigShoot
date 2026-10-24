import SwiftUI

struct CollectionPeriodPicker: View {
    @Binding var window: CollectionWindow
    @Binding var filter: DashboardLedgerFilter
    @Binding var rangeStart: Date
    @Binding var rangeEnd: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsRange = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(CollectionWindow.allCases.enumerated()), id: \.element.id) { index, item in
                if showsDivider(before: index) {
                    Capsule()
                        .fill(.primary.opacity(0.18))
                        .frame(width: 1, height: 12)
                        .accessibilityHidden(true)
                }
                Button(item.title) {
                    select(item)
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(window == item ? .semibold : .regular))
                .foregroundStyle(window == item ? StudioDesign.ink : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    if window == item {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(StudioDesign.gold)
                    }
                }
                .contentShape(.rect)
                .accessibilityAddTraits(window == item ? .isSelected : [])
                .accessibilityHint(hint(for: item))
                .collectionRangePopover(
                    attached: item == .range,
                    isPresented: $showsRange,
                    phrase: CollectionWindow.phrase(from: rangeStart, to: rangeEnd),
                    start: $rangeStart,
                    end: $rangeEnd
                )
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(reduceMotion ? nil : .snappy, value: window)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Collected period")
        .onChange(of: window) { _, newWindow in
            if newWindow != .range {
                showsRange = false
            }
        }
        .onChange(of: rangeStart) { _, _ in
            clearStaleBucket()
        }
        .onChange(of: rangeEnd) { _, _ in
            clearStaleBucket()
        }
    }

    private func showsDivider(before index: Int) -> Bool {
        guard index > 0 else { return false }
        let items = CollectionWindow.allCases
        return window != items[index - 1] && window != items[index]
    }

    private func hint(for item: CollectionWindow) -> String {
        if item == .range {
            return "Choose a start and end date"
        }
        return "Show cash received \(item.spokenTitle.lowercased())"
    }

    private func select(_ item: CollectionWindow) {
        if item == .range {
            if window == .range {
                showsRange.toggle()
                return
            }
            window = .range
            filter = .cash(.range)
            showsRange = true
            return
        }
        showsRange = false
        window = item
        filter = .cash(item)
    }

    private func clearStaleBucket() {
        guard window == .range, filter.bucketStart != nil else { return }
        filter = .cash(.range)
    }
}

private extension View {
    @ViewBuilder func collectionRangePopover(
        attached: Bool,
        isPresented: Binding<Bool>,
        phrase: String,
        start: Binding<Date>,
        end: Binding<Date>
    ) -> some View {
        if attached {
            self
                .accessibilityValue(phrase)
                .popover(isPresented: isPresented, arrowEdge: .top) {
                    CollectionRangePopover(start: start, end: end)
                }
        } else {
            self
        }
    }
}
