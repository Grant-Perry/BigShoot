import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum QuoteScope: String, CaseIterable, Identifiable {
    case open
    case signed
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open"
        case .signed: "Signed"
        case .all: "All"
        }
    }

    func includes(_ quote: Quote) -> Bool {
        switch self {
        case .open: quote.status == .draft || quote.status == .sent
        case .signed: quote.status == .signed
        case .all: true
        }
    }
}

struct QuoteWorkspace: View {
    @Binding var selection: PersistentIdentifier?
    @Binding var showNewQuote: Bool
    var onOpenInvoice: (PersistentIdentifier) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Quote.quoteDate, order: .reverse) private var quotes: [Quote]
    @State private var scope: QuoteScope = .open
    @State private var search = ""
    @State private var previewQuote: Quote?
    @State private var previewAgreementOnly = false
    @State private var editingQuote: Quote?
    @State private var editingAgreement: Quote?
    @State private var mailNote: String?
    @State private var shareItem: QuoteShare?
    @State private var sendChoice: QuoteShare?
    @State private var convertError: String?
    @State private var deleteTarget: Quote?
    @State private var evidenceImporter = false
    @State private var pendingConvert: Quote?
    @State private var evidenceData: Data?

    private var filtered: [Quote] {
        quotes.filter { quote in
            guard scope.includes(quote) else { return false }
            guard !search.isEmpty else { return true }
            return quote.displayNumber.localizedStandardContains(search)
                || quote.clientName.localizedStandardContains(search)
                || quote.job?.name.localizedStandardContains(search) == true
        }
    }

    private var selected: Quote? {
        quotes.first { $0.persistentModelID == selection }
    }

    var body: some View {
        HStack(spacing: 0) {
            quoteList
                .frame(width: 380)
            Divider()
            Group {
                if let selected {
                    QuoteDetailView(
                        quote: selected,
                        onPreview: {
                            previewAgreementOnly = false
                            previewQuote = selected
                        },
                        onPreviewContract: {
                            previewAgreementOnly = true
                            previewQuote = selected
                        },
                        onSend: { send(selected) },
                        onEdit: { editingQuote = selected },
                        onEditAgreement: { editingAgreement = selected },
                        onMarkSigned: { beginConvert(selected) },
                        onOpenInvoice: onOpenInvoice,
                        onDelete: { deleteTarget = selected }
                    )
                } else {
                    StudioEmptyState(
                        title: "No quote selected",
                        message: "Build a quote, attach an agreement, and email it for signature.",
                        symbol: "doc.plaintext"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioSceneBackground())
        }
        .background(QuoteSharePicker(share: shareItem) { share, didShare in
            shareItem = nil
            if didShare { markSent(share.quote) }
        })
        .confirmationDialog(
            "Send quote",
            isPresented: sendChoicePresented,
            titleVisibility: .visible,
            presenting: sendChoice
        ) { share in
            Button("Email…") {
                switch QuoteComposer.email(share) {
                case .composed:
                    break
                case .attachedInApp(let app):
                    let to = share.recipients.joined(separator: ", ")
                    mailNote = "\(app) opened a new email with the PDF attached. Add the recipient (\(to.isEmpty ? "the client" : to)) and the subject “\(share.subject)”, then paste the message, which is copied."
                case .manualAttach:
                    mailNote = "Your default mail app is web mail, which can’t attach files by itself. The PDF is shown in Finder and copied: drag it into the new email, or paste it."
                }
                markSent(share.quote)
            }
            Button("Share…") { shareItem = share }
            Button("Show PDF in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([share.pdfURL])
            }
            Button("Cancel", role: .cancel) {}
        } message: { share in
            Text("Quote \(share.quote.displayNumber) is ready as a PDF.")
        }
        .sheet(isPresented: $showNewQuote) {
            NewQuoteSheet()
        }
        .sheet(item: $editingQuote) { quote in
            NewQuoteSheet(existing: quote)
        }
        .sheet(item: $editingAgreement) { quote in
            QuoteAgreementSheet(quote: quote)
        }
        .sheet(item: $previewQuote) { quote in
            QuotePDFPreviewSheet(quote: quote, agreementOnly: previewAgreementOnly)
        }
        .alert("Mail", isPresented: mailPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mailNote ?? "")
        }
        .alert("Couldn’t convert", isPresented: convertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(convertError ?? "")
        }
        .alert(
            "Delete quote?",
            isPresented: deletePresented
        ) {
            Button("Delete", role: .destructive) {
                if let deleteTarget {
                    modelContext.delete(deleteTarget)
                    try? modelContext.save()
                    selection = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the quote. Signed invoices already created stay on the books.")
        }
        .confirmationDialog(
            "Mark signed and convert?",
            isPresented: convertConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Convert to Invoice") {
                convert(evidence: nil)
            }
            Button("Attach Signed PDF…") {
                evidenceImporter = true
            }
            Button("Cancel", role: .cancel) {
                pendingConvert = nil
            }
        } message: {
            Text("Creates a pending invoice from this quote’s lines. Attach the client’s signed PDF if you have it.")
        }
        .fileImporter(
            isPresented: $evidenceImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                evidenceData = try? Data(contentsOf: url)
                convert(evidence: evidenceData)
            case .failure(let error):
                convertError = error.localizedDescription
                pendingConvert = nil
            }
        }
    }

    private var sendChoicePresented: Binding<Bool> {
        Binding(get: { sendChoice != nil }, set: { if !$0 { sendChoice = nil } })
    }

    private var mailPresented: Binding<Bool> {
        Binding(get: { mailNote != nil }, set: { if !$0 { mailNote = nil } })
    }

    private var convertPresented: Binding<Bool> {
        Binding(get: { convertError != nil }, set: { if !$0 { convertError = nil } })
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var convertConfirmPresented: Binding<Bool> {
        Binding(
            get: { pendingConvert != nil && !evidenceImporter },
            set: { if !$0 && !evidenceImporter { pendingConvert = nil } }
        )
    }

    private var quoteList: some View {
        VStack(spacing: 0) {
            Picker("Scope:", selection: $scope) {
                ForEach(QuoteScope.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)
            StudioColumnSearch(text: $search, prompt: "Number, client, or job", findLabel: "Find Quote")
            List(filtered, selection: $selection) { quote in
                QuoteListRow(quote: quote)
                    .tag(quote.persistentModelID)
            }
            .listStyle(.sidebar)
        }
        .toolbar {
            ToolbarItem {
                Button("New Quote", systemImage: "plus") {
                    showNewQuote = true
                }
            }
        }
    }

    private func send(_ quote: Quote) {
        if AgreementAskField.hasUnresolvedAsks(in: quote.agreementHTML) {
            mailNote = "Fill the Ask fields on this quote’s agreement before emailing."
            return
        }
        do {
            if quote.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                quote.number = QuoteMath.nextNumber(among: quotes.map(\.number))
                try modelContext.save()
            }
        } catch {
            mailNote = error.localizedDescription
            return
        }
        guard let share = QuoteComposer.prepare(quote) else {
            mailNote = "Couldn’t create the quote PDF. Preview the PDF and save it to send yourself."
            return
        }
        sendChoice = share
    }

    /// Marks a draft as sent only once the user has actually picked a way to share it.
    private func markSent(_ quote: Quote) {
        guard quote.status == .draft else { return }
        quote.status = .sent
        quote.sentAt = quote.sentAt ?? .now
        do {
            try modelContext.save()
        } catch {
            mailNote = error.localizedDescription
        }
    }

    private func beginConvert(_ quote: Quote) {
        if AgreementAskField.hasUnresolvedAsks(in: quote.agreementHTML) {
            convertError = "Fill the Ask fields on this quote’s agreement before converting."
            return
        }
        pendingConvert = quote
        evidenceData = nil
    }

    private func convert(evidence: Data?) {
        guard let quote = pendingConvert else { return }
        pendingConvert = nil
        do {
            let invoice = try QuoteConverter.convertToInvoice(quote, evidence: evidence, in: modelContext)
            selection = quote.persistentModelID
            onOpenInvoice(invoice.persistentModelID)
        } catch {
            convertError = error.localizedDescription
        }
    }
}
