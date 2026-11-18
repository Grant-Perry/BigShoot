import SwiftUI

struct CollectionRangePopover: View {
    @Binding var start: Date
    @Binding var end: Date

    var body: some View {
        StudioLabeledStack {
            StudioLabeledRow("Start") {
                DatePicker("Start", selection: $start, in: ...end, displayedComponents: .date)
                    .labelsHidden()
            }
            StudioLabeledRow("End") {
                DatePicker("End", selection: $end, in: start..., displayedComponents: .date)
                    .labelsHidden()
            }
        }
        .datePickerStyle(.compact)
        .padding(16)
        .frame(minWidth: 260)
    }
}
