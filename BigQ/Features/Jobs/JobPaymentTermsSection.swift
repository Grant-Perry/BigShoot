import SwiftData
import SwiftUI

struct JobPaymentTermsSection: View {
    @Environment(\.modelContext) private var modelContext
    var job: Job

    @State private var showBuilder = false
    @State private var draftMode: QuotePaymentScheduleMode = .none
    @State private var draftTerms: [DraftPaymentTerm] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Payment terms")
                    .font(.headline)
                Spacer()
                Button(job.paymentScheduleMode == .none ? "Add Schedule…" : "Edit Schedule…") {
                    prepareDraftFromJob()
                    showBuilder = true
                }
            }
            switch job.paymentScheduleMode {
            case .none:
                Text("No payment schedule yet. Terms here copy into new quotes for this job.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .scheduled, .custom:
                ForEach(displayTerms) { term in
                    Text(QuotePaymentSchedule.summaryLine(term))
                        .font(.callout)
                }
                completenessBadge
            }
        }
        .sheet(isPresented: $showBuilder) {
            PaymentScheduleSheet(
                scheduleMode: $draftMode,
                paymentTerms: $draftTerms,
                total: 0,
                eventDate: job.eventDate,
                onCommit: commitDraftToJob
            )
        }
    }

    private var displayTerms: [DraftPaymentTerm] {
        var drafts = QuotePaymentSchedule.drafts(from: job)
        QuotePaymentSchedule.recalculate(&drafts, total: 0)
        return drafts
    }

    @ViewBuilder
    private var completenessBadge: some View {
        let summary = QuotePaymentSchedule.completenessSummary(terms: displayTerms, total: 0)
        Text(summary.text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(summary.isComplete ? StudioDesign.paid : StudioDesign.rose)
    }

    private func prepareDraftFromJob() {
        draftMode = job.paymentScheduleMode
        draftTerms = QuotePaymentSchedule.drafts(from: job)
        QuotePaymentSchedule.recalculate(&draftTerms, total: 0)
    }

    private func commitDraftToJob() {
        JobPaymentSchedule.replaceTerms(
            on: job,
            mode: draftMode,
            drafts: draftTerms,
            in: modelContext
        )
        try? modelContext.save()
    }
}
