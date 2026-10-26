import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct InvoicePDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    var invoice: Invoice
    var note: String?
    /// Submit only. The share icon does not call this.
    var onSubmit: () -> Void = {}

    @State private var shareItems: [URL] = []
    @State private var shareFromIcon = false
    @State private var shareFromSubmit = false
    @State private var shareError: String?

    private var data: Data { InvoicePDFRenderer.render(invoice) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(invoice.displayNumber)
                    .font(StudioDesign.displayTitle)
                Spacer()
                shareButton
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
                StudioEmptyState(title: "Couldn’t draw the PDF", message: "Try the invoice again.", symbol: "doc")
            }
            HStack {
                Spacer()
                Button("Submit", action: submit)
                    .buttonStyle(.borderedProminent)
                    .background {
                        InvoiceSharePicker(items: shareItems, isPresented: $shareFromSubmit)
                    }
                    .help("Stamp Invoice Submitted and share the PDF")
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 860)
        .studioActive()
    }

    private var shareButton: some View {
        Button(action: share) {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Share")
        .help("Share the PDF")
        .background {
            InvoiceSharePicker(items: shareItems, isPresented: $shareFromIcon)
        }
    }

    private func share() {
        guard let url = writePDF() else { return }
        shareItems = [url]
        shareFromIcon = true
    }

    private func submit() {
        guard let url = writePDF() else { return }
        onSubmit()
        shareItems = [url]
        shareFromSubmit = true
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

    private func writePDF() -> URL? {
        let safeNumber = invoice.displayNumber
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Invoice-\(safeNumber).pdf")
        do {
            try data.write(to: url, options: .atomic)
            shareError = nil
            return url
        } catch {
            shareError = "Couldn’t create the PDF."
            DebugPrint(mode: .error, "PDF share failed: \(error.localizedDescription)")
            return nil
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

/// Mac share sheet. Presenting it does not change Invoice Submitted.
private struct InvoiceSharePicker: NSViewRepresentable {
    var items: [URL]
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented else {
            context.coordinator.didPresent = false
            return
        }
        guard !context.coordinator.didPresent, nsView.window != nil else { return }
        context.coordinator.didPresent = true
        let picker = NSSharingServicePicker(items: items as [Any])
        picker.delegate = context.coordinator
        context.coordinator.picker = picker
        picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var picker: NSSharingServicePicker?
        var didPresent = false

        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            didChoose service: NSSharingService?
        ) {
            picker = nil
            didPresent = false
        }
    }
}
