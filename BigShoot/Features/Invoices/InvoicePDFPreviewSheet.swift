import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct InvoicePDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    var invoice: Invoice
    var note: String?

    private var data: Data { InvoicePDFRenderer.render(invoice) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(invoice.displayNumber)
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
            if let document = PDFDocument(data: data) {
                InvoicePDFView(document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StudioEmptyState(title: "Couldn’t draw the PDF", message: "Try the invoice again.", symbol: "doc")
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 860)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Invoice-\(invoice.displayNumber).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            DebugPrint(mode: .error, "PDF save failed: \(error.localizedDescription)")
        }
    }
}

struct InvoicePDFView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.document = document
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        view.document = document
    }
}
