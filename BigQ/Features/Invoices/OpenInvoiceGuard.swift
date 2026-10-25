import SwiftData
import SwiftUI

/// Shown before a second open invoice can be saved, or before a new job is used to step around one.
struct OpenInvoiceGuard: View {
    var title: String
    var invoices: [Invoice]
    var showsJobName: Bool
    var continueTitle: String
    var onOpen: (Invoice) -> Void
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            ForEach(Array(invoices.enumerated()), id: \.element.persistentModelID) { index, invoice in
                VStack(alignment: .leading, spacing: 4) {
                    if showsJobName, let job = invoice.job {
                        Text(job.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(invoice.displayNumber)
                        .font(.headline)
                    Text("Due \(StudioDay.string(invoice.dueDate))")
                        .foregroundStyle(.secondary)
                    Text("\(StudioMoney.string(invoice.balance)) balance")
                        .font(StudioDesign.metric(16))
                        .monospacedDigit()
                    openButton(invoice, isDefault: index == 0)
                }
            }
            Button(continueTitle, action: onContinue)
                .buttonStyle(.bordered)
        }
        .padding(StudioDesign.Spacing.card)
        .paperCard()
    }

    @ViewBuilder
    private func openButton(_ invoice: Invoice, isDefault: Bool) -> some View {
        let button = Button("Open it") { onOpen(invoice) }
            .buttonStyle(.borderedProminent)
        if isDefault {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }
}

/// Quiet reminder after someone deliberately chooses a second invoice.
struct OpenInvoiceAcknowledgement: View {
    var invoices: [Invoice]
    var onOpen: (Invoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This will be another invoice on this job.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(invoices) { invoice in
                Button("Open \(invoice.displayNumber) instead") {
                    onOpen(invoice)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
