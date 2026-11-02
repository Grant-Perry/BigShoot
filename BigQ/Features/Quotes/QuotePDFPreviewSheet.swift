import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct QuotePDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    var quote: Quote
    var note: String?

    @State private var shareError: String?

    private var data: Data { QuotePDFRenderer.render(quote) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(quote.displayNumber)
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
            if let document = PDFDocument(data: data) {
                InvoicePDFView(document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StudioEmptyState(title: "Couldn’t draw the PDF", message: "Try the quote again.", symbol: "doc.plaintext")
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 860)
        .studioActive()
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Quote-\(quote.displayNumber).pdf"
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
