import SwiftUI

struct CollectionRangePopover: View {
    @Binding var start: Date
    @Binding var end: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Start", selection: $start, in: ...end, displayedComponents: .date)
            DatePicker("End", selection: $end, in: start..., displayedComponents: .date)
        }
        .datePickerStyle(.compact)
        .padding(16)
        .frame(minWidth: 260)
    }
}
