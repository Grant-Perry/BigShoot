import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct QuotePDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    var quote: Quote
    var note: String?
    /// When true, only the merged agreement pages — no quote pricing sheet.
    var agreementOnly = false

    @State private var shareError: String?

    private var data: Data {
        agreementOnly
            ? QuotePDFRenderer.renderAgreementOnly(quote)
            : QuotePDFRenderer.render(quote)
    }

    private var heading: String {
        if agreementOnly {
            let title = quote.agreementTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "Agreement" : title
        }
        return quote.displayNumber
    }

    private var emptyMessage: String {
        agreementOnly
            ? "Add agreement text, then preview again."
            : "Try the quote again."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(heading)
                    .font(StudioDesign.displayTitle)
                Spacer()
                Button("Save PDF…", action: save)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            if let note {
                Text(note)
                    .foregroundStyle(.secondary)
            }
            if let shareError {
                Text(shareError)
                    .foregroundStyle(.red)
            }
            if !data.isEmpty, let document = PDFDocument(data: data) {
                InvoicePDFView(document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StudioEmptyState(
                    title: "Couldn’t draw the PDF",
                    message: emptyMessage,
                    symbol: "doc.plaintext"
                )
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 860)
        .studioActive()
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let stub = agreementOnly ? "Agreement" : "Quote"
        panel.nameFieldStringValue = "\(stub)-\(quote.displayNumber).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            shareError = nil
        } catch {
            shareError = "Couldn’t save the PDF."
            DebugPrint(mode: .error, "Quote PDF save failed: \(error.localizedDescription)")
        }
    }
}
