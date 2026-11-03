import Foundation
import SwiftData

enum JobPaymentSchedule {
    static func replaceTerms(
        on job: Job,
        mode: QuotePaymentScheduleMode,
        drafts: [DraftPaymentTerm],
        in context: ModelContext
    ) {
        for term in job.paymentTerms {
            context.delete(term)
        }
        job.paymentTerms.removeAll()
        job.paymentScheduleMode = mode
        guard mode != .none else { return }
        for (position, draft) in drafts.enumerated() {
            let term = JobPaymentTerm(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                position: position,
                amountMode: draft.amountMode,
                percent: draft.percent,
                fixedAmount: draft.fixedAmount,
                dueMode: draft.dueMode,
                daysBeforeEvent: draft.daysBeforeEvent,
                fixedDueDate: draft.fixedDueDate,
                amount: draft.amount
            )
            term.job = job
            context.insert(term)
        }
    }
}
