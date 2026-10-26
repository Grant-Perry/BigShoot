import SwiftData
import SwiftUI

/// Rate field, schedule menu, and the dollar tax that rate produces.
struct InvoiceTaxControls: View {
    @Bindable var draft: InvoiceDraftModel
    var schedules: [TaxSchedule]

    @State private var addingSchedule = false
    @FocusState private var rateFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Toggle("Charge Tax:", isOn: $draft.invoiceTaxable)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                Text(draft.invoiceTaxable ? StudioMoney.string(draft.tax) : "No tax")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Tax amount")
                if draft.invoiceTaxable {
                    HStack(spacing: 8) {
                        Text("Rate:")
                            .foregroundStyle(.secondary)
                        TextField("Rate", text: $draft.taxRateText)
                            .focused($rateFocused)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .onSubmit { draft.commitTaxRate(schedules: schedules) }
                            .accessibilityLabel("Tax rate")
                        Text("%")
                            .foregroundStyle(.secondary)
                        Text("Saved rate:")
                            .foregroundStyle(.secondary)
                        Picker("Saved rate:", selection: schedulePick) {
                            Text("Custom rate").tag(SchedulePick.none)
                            ForEach(schedules) { schedule in
                                Text("\(schedule.name) · \(TaxRateInput.percentText(for: schedule.rate))%")
                                    .tag(SchedulePick.saved(schedule.persistentModelID))
                            }
                            Divider()
                            Text("Add Schedule…").tag(SchedulePick.add)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                }
            }
            Text(taxExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .onChange(of: rateFocused) { _, focused in
            if !focused { draft.commitTaxRate(schedules: schedules) }
        }
        .onChange(of: draft.invoiceTaxable) { _, isOn in
            guard isOn else { return }
            Task { @MainActor in
                rateFocused = true
            }
        }
        .animation(.smooth(duration: 0.15), value: draft.invoiceTaxable)
        .sheet(isPresented: $addingSchedule) {
            TaxScheduleSheet(startingRate: draft.taxRateText) { schedule in
                draft.apply(schedule: schedule)
            }
        }
    }

    private var taxExplanation: String {
        draft.invoiceTaxable
            ? "Added only on lines with Tax checked."
            : "Off for this invoice. Line checkboxes stay as they are."
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
        .studioActive()
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
