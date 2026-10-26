import SwiftUI

/// Checkbox that stamps the pipeline time, with the title opening a calendar to change it.
struct InvoiceSubmittedField: View {
    @Binding var submittedAt: Date?

    @State private var showCalendar = false
    @State private var calendarDate = Date.now

    var body: some View {
        HStack(spacing: 8) {
            Button(action: openCalendar) {
                HStack(spacing: 4) {
                    Text("Invoice Submitted:")
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Change the submitted date")
            Toggle(
                "Invoice Submitted",
                isOn: Binding(
                    get: { submittedAt != nil },
                    set: { isOn in
                        submittedAt = isOn ? (submittedAt ?? .now) : nil
                    }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            if let submittedAt {
                Button(StudioStamp.string(submittedAt), action: openCalendar)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help("Change the submitted date")
            }
        }
        .fixedSize()
        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
            DatePicker(
                "Submitted",
                selection: $calendarDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(12)
            .frame(width: 320)
        }
        .onChange(of: calendarDate) { _, newValue in
            guard showCalendar else { return }
            submittedAt = newValue
        }
    }

    private func openCalendar() {
        calendarDate = submittedAt ?? .now
        showCalendar = true
    }
}
