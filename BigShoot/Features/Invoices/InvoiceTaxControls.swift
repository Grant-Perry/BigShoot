import SwiftData
import SwiftUI

/// Rate field, schedule menu, and the dollar tax that rate produces.
struct InvoiceTaxControls: View {
    @Bindable var draft: InvoiceDraftModel
    var schedules: [TaxSchedule]

    @State private var addingSchedule = false
    @FocusState private var rateFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Invoice Taxable", isOn: $draft.invoiceTaxable)
                .toggleStyle(.checkbox)
            HStack(spacing: 8) {
                Text("Tax")
                TextField("Rate", text: $draft.taxRateText)
                    .focused($rateFocused)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .onSubmit { draft.commitTaxRate(schedules: schedules) }
                Text("%")
                    .foregroundStyle(.secondary)
                Picker("Schedule", selection: schedulePick) {
                    Text("None").tag(SchedulePick.none)
                    ForEach(schedules) { schedule in
                        Text("\(schedule.name) · \(TaxRateInput.percentText(for: schedule.rate))%")
                            .tag(SchedulePick.saved(schedule.persistentModelID))
                    }
                    Divider()
                    Text("Add Schedule…").tag(SchedulePick.add)
                }
                .frame(maxWidth: 200)
            }
            .disabled(!draft.invoiceTaxable)
            Text("Tax amount \(StudioMoney.string(draft.tax))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .disabled(!draft.invoiceTaxable)
        }
        .onChange(of: rateFocused) { _, focused in
            if !focused { draft.commitTaxRate(schedules: schedules) }
        }
        .sheet(isPresented: $addingSchedule) {
            TaxScheduleSheet(startingRate: draft.taxRateText) { schedule in
                draft.apply(schedule: schedule)
            }
        }
    }

    private var schedulePick: Binding<SchedulePick> {
        Binding(
            get: {
                guard let match = schedules.first(where: {
                    $0.name == draft.taxScheduleName && $0.rate == draft.taxRate
                }) else { return .none }
                return .saved(match.persistentModelID)
            },
            set: { pick in
                switch pick {
                case .none:
                    draft.clearScheduleSelection()
                case .add:
                    addingSchedule = true
                case .saved(let id):
                    if let schedule = schedules.first(where: { $0.persistentModelID == id }) {
                        draft.apply(schedule: schedule)
                    }
                }
            }
        )
    }
}

private enum SchedulePick: Hashable {
    case none
    case add
    case saved(PersistentIdentifier)
}

private struct TaxScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var startingRate: String
    var onSave: (TaxSchedule) -> Void

    @State private var name = ""
    @State private var rateText = ""
    @State private var errorMessage: String?
    @FocusState private var rateFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add tax schedule")
                .font(StudioDesign.displayTitle)
            TextField("Name", text: $name)
            HStack {
                TextField("Rate", text: $rateText)
                    .focused($rateFocused)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88)
                    .onSubmit(commitRate)
                Text("%")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("6.6 and 0.066 both mean 6.6%.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Add", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { rateText = startingRate }
        .onChange(of: rateFocused) { _, focused in
            if !focused { commitRate() }
        }
    }

    private func commitRate() {
        guard let fraction = TaxRateInput.fraction(from: rateText) else { return }
        rateText = TaxRateInput.percentText(for: fraction)
    }

    private func save() {
        commitRate()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fraction = TaxRateInput.fraction(from: rateText), fraction > 0 else {
            errorMessage = "Enter a tax rate."
            return
        }
        let schedule = TaxSchedule(name: trimmed, rate: fraction)
        modelContext.insert(schedule)
        do {
            try modelContext.save()
            onSave(schedule)
            dismiss()
        } catch {
            errorMessage = "That schedule name is already in the list."
        }
    }
}
