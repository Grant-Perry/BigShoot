import SwiftData
import SwiftUI

struct ImportOfferSheet: View {
    @Environment(\.modelContext) private var modelContext
    var model: ShootQImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ShootQ books")
                .font(StudioDesign.displayTitle)
            Text("Import contacts, jobs, invoices, payments, line items, and contracts. Sent mail stays in the folder.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.isImporting {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.stepTitle)
                    ProgressView(value: model.fraction)
                }
            } else if let summary = model.summary {
                summaryView(summary)
            } else {
                Text(model.discoveredFolder == nil
                     ? "Point BigQ at the shootq-export folder."
                     : model.folderTitle)
                    .font(.callout)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if model.summary == nil {
                    Button("Not Now", action: model.decline)
                        .disabled(model.isImporting)
                    Spacer()
                    Button("Choose Folder…") {
                        Task { await model.chooseAnother(context: modelContext) }
                    }
                    .disabled(model.isImporting)
                    Button("Import") {
                        Task { await model.importPreferred(context: modelContext) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isImporting)
                } else {
                    Spacer()
                    Button("Done") { model.isPresentingOffer = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 520)
    }

    private func summaryView(_ summary: ShootQImportSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The books are in.")
                .font(.headline)
            Text("\(summary.contacts) contacts · \(summary.jobs) jobs · \(summary.invoices) invoices")
            Text("\(summary.schedule) scheduled payments · \(summary.receipts) receipts")
            Text("\(summary.lines) line items · \(summary.catalog) catalog names")
            Text("\(summary.contracts) contracts")
            if summary.skippedPartialLines > 0 {
                Text("Skipped \(summary.skippedPartialLines) unfinished line-item rows.")
                    .foregroundStyle(.secondary)
            }
            Text("Line items from \(summary.lineSource).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
