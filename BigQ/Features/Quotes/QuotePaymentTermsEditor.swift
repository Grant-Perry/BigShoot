import SwiftUI

/// Compact summary + button on the quote form.
struct QuotePaymentTermsSection: View {
    @Bindable var draft: QuoteDraftModel
    @State private var showBuilder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Payment terms")
                    .font(.headline)
                Spacer()
                Button(draft.paymentScheduleMode == .none ? "Add Schedule…" : "Edit Schedule…") {
                    showBuilder = true
                }
            }
            switch draft.paymentScheduleMode {
            case .none:
                Text("No payment schedule yet. Add scheduled or custom terms that total 100%.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .scheduled, .custom:
                ForEach(draft.paymentTerms) { term in
                    Text(QuotePaymentSchedule.summaryLine(term))
                        .font(.callout)
                }
                completenessBadge
            }
        }
        .sheet(isPresented: $showBuilder) {
            QuotePaymentScheduleSheet(draft: draft)
        }
        .onChange(of: draft.pricing.total) { _, _ in
            draft.refreshPaymentAmounts()
        }
    }

    @ViewBuilder
    private var completenessBadge: some View {
        let summary = QuotePaymentSchedule.completenessSummary(
            terms: draft.paymentTerms,
            total: draft.pricing.total
        )
        Text(summary.text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(summary.isComplete ? StudioDesign.paid : StudioDesign.rose)
    }
}

struct QuotePaymentScheduleSheet: View {
    @Bindable var draft: QuoteDraftModel

    var body: some View {
        PaymentScheduleSheet(
            scheduleMode: $draft.paymentScheduleMode,
            paymentTerms: $draft.paymentTerms,
            total: draft.pricing.total,
            eventDate: draft.pricing.job?.eventDate
        )
    }
}

struct PaymentScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var scheduleMode: QuotePaymentScheduleMode
    @Binding var paymentTerms: [DraftPaymentTerm]
    var total: Decimal
    var eventDate: Date?
    var onCommit: (() -> Void)?

    @State private var mode: QuotePaymentScheduleMode
    @State private var scheduledCount = 4
    @State private var scheduledStart = Date.now
    @State private var editingCustom: DraftPaymentTerm?

    init(
        scheduleMode: Binding<QuotePaymentScheduleMode>,
        paymentTerms: Binding<[DraftPaymentTerm]>,
        total: Decimal,
        eventDate: Date? = nil,
        onCommit: (() -> Void)? = nil
    ) {
        _scheduleMode = scheduleMode
        _paymentTerms = paymentTerms
        self.total = total
        self.eventDate = eventDate
        self.onCommit = onCommit
        _mode = State(initialValue: scheduleMode.wrappedValue == .none ? .custom : scheduleMode.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modePicker
                    if mode == .scheduled {
                        scheduledSection
                    } else {
                        customSection
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 640)
        .onAppear {
            refreshAmounts()
        }
        .sheet(item: $editingCustom) { term in
            CustomPaymentTermEditor(
                term: term,
                total: total,
                eventDate: eventDate,
                onSave: { saved in
                    if let index = paymentTerms.firstIndex(where: { $0.id == saved.id }) {
                        paymentTerms[index] = saved
                    } else {
                        paymentTerms.append(saved)
                    }
                    scheduleMode = .custom
                    refreshAmounts()
                    editingCustom = nil
                },
                onCancel: { editingCustom = nil }
            )
        }
    }

    private func refreshAmounts() {
        QuotePaymentSchedule.recalculate(&paymentTerms, total: total)
    }

    private var header: some View {
        HStack {
            Text("Select a Payment Schedule")
                .font(StudioDesign.displayTitle)
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
        }
        .padding(20)
    }

    private var modePicker: some View {
        VStack(spacing: 8) {
            modeRow(.scheduled, subtitle: "Equal payments. Monthly dates to start — edit any date.")
            modeRow(.custom, subtitle: "Percentages, remaining balance, signature / event / fixed due dates.")
        }
    }

    private func modeRow(_ value: QuotePaymentScheduleMode, subtitle: String) -> some View {
        Button {
            mode = value
            if value == .scheduled, paymentTerms.isEmpty || scheduleMode != .scheduled {
                // Keep existing until Generate is pressed.
            }
            if value == .custom {
                scheduleMode = .custom
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mode == value ? StudioDesign.gold : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(mode == value ? StudioDesign.gold.opacity(0.7) : Color.secondary.opacity(0.25))
            )
        }
        .buttonStyle(.plain)
    }

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Stepper("Payments: \(scheduledCount)", value: $scheduledCount, in: 1...24)
                DatePicker("Start", selection: $scheduledStart, displayedComponents: .date)
            }
            Button("Generate equal payments") {
                scheduleMode = .scheduled
                paymentTerms = QuotePaymentSchedule.generateScheduled(
                    total: total,
                    count: scheduledCount,
                    starting: scheduledStart
                )
                mode = .scheduled
            }
            .buttonStyle(.borderedProminent)

            if scheduleMode == .scheduled {
                Text("Amounts stay equal. Change any due date — they don’t have to stay monthly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach($paymentTerms) { $term in
                    HStack {
                        TextField("Title", text: $term.title)
                            .frame(maxWidth: 140)
                        Text(StudioMoney.string(term.amount))
                            .monospacedDigit()
                            .frame(width: 90, alignment: .trailing)
                        DatePicker(
                            "Due",
                            selection: $term.fixedDueDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                    .onChange(of: term.fixedDueDate) { _, _ in
                        term.dueMode = .fixedDate
                    }
                }
                completeness
            }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(paymentTerms) { term in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(term.title.isEmpty ? "Untitled" : term.title)
                        Text(QuotePaymentSchedule.summaryLine(term))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit") { editingCustom = term }
                    Button("Remove", role: .destructive) {
                        paymentTerms.removeAll { $0.id == term.id }
                        refreshAmounts()
                    }
                }
                .padding(.vertical, 4)
            }
            Button("Add payment…") {
                editingCustom = DraftPaymentTerm(
                    title: "",
                    amountMode: paymentTerms.isEmpty ? .percentOfTotal : .remainingBalance,
                    percent: paymentTerms.isEmpty ? 50 : 0,
                    dueMode: .signature
                )
            }
            completeness
        }
    }

    private var completeness: some View {
        let summary = QuotePaymentSchedule.completenessSummary(terms: paymentTerms, total: total)
        return Group {
            if paymentTerms.isEmpty {
                Text(summary.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(summary.text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.isComplete ? StudioDesign.paid : StudioDesign.rose)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Clear schedule", role: .destructive) {
                scheduleMode = .none
                paymentTerms = []
                onCommit?()
                dismiss()
            }
            Spacer()
            Button("Done") {
                if mode == .scheduled {
                    scheduleMode = paymentTerms.isEmpty ? .none : .scheduled
                } else {
                    scheduleMode = paymentTerms.isEmpty ? .none : .custom
                }
                refreshAmounts()
                onCommit?()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(
                (mode != .none && !paymentTerms.isEmpty)
                    && !QuotePaymentSchedule.isComplete(paymentTerms, total: total)
            )
        }
        .padding(20)
    }
}

private struct CustomPaymentTermEditor: View {
    @State var term: DraftPaymentTerm
    var total: Decimal
    var eventDate: Date?
    var onSave: (DraftPaymentTerm) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Payment")
                .font(StudioDesign.displayTitle)
            TextField("Schedule title", text: $term.title)
            Picker("Calculation", selection: $term.amountMode) {
                Text(QuotePaymentAmountMode.percentOfTotal.title).tag(QuotePaymentAmountMode.percentOfTotal)
                Text(QuotePaymentAmountMode.remainingBalance.title).tag(QuotePaymentAmountMode.remainingBalance)
                Text(QuotePaymentAmountMode.fixedAmount.title).tag(QuotePaymentAmountMode.fixedAmount)
            }
            .onChange(of: term.amountMode) { _, mode in
                if mode == .equalShare { term.amountMode = .percentOfTotal }
            }
            if term.amountMode == .percentOfTotal {
                HStack {
                    TextField("Percent", value: $term.percent, format: .number)
                        .frame(width: 80)
                    Text("% of total (\(StudioMoney.string(total)))")
                        .foregroundStyle(.secondary)
                }
            }
            if term.amountMode == .fixedAmount {
                TextField("Amount", value: $term.fixedAmount, format: .currency(code: "USD"))
                    .frame(width: 140)
            }
            Picker("Due", selection: $term.dueMode) {
                ForEach(QuotePaymentDueMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if term.dueMode == .daysBeforeEvent {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    TextField("Days", value: $term.daysBeforeEvent, format: .number)
                        .frame(width: 80)
                    Text("days before event")
                        .foregroundStyle(.secondary)
                    if let due = QuotePaymentSchedule.resolveDue(
                        term,
                        signatureDate: nil,
                        eventDate: eventDate
                    ) {
                        Text("· \(StudioDay.string(due))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("· Set event date on the job to preview")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if term.dueMode == .fixedDate {
                DatePicker("Date", selection: $term.fixedDueDate, displayedComponents: .date)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save") {
                    term.daysBeforeEvent = min(730, max(0, term.daysBeforeEvent))
                    onSave(term)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
