import SwiftData
import SwiftUI

struct InvoiceMailSession: Identifiable {
    let id = UUID()
    var invoice: Invoice
    var existing: InvoiceEmail?
    var linkWarning: String?
}

struct InvoiceEmailComposer: View {
    var invoice: Invoice
    var existing: InvoiceEmail?
    var linkWarning: String?
    var onSent: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmailTemplate.name) private var templates: [EmailTemplate]

    @State private var recipient: String
    @State private var subject: String
    @State private var bodyText: String
    @State private var templateName: String
    @State private var templatePick: InvoiceMailPick
    @State private var appliedSubject: String
    @State private var appliedBody: String
    @State private var files: [MailFileDraft]
    @State private var importingFiles = false
    @State private var fileError: String?
    @State private var suppressPick = false
    @State private var pendingPick: InvoiceMailPick?
    @State private var confirmReplace = false
    @State private var confirmDelete = false
    @State private var savingTemplate = false
    @State private var templateTitle = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var letterInsertion: QuoteLetterInsertion?
    @State private var showingPreview = false

    init(invoice: Invoice, existing: InvoiceEmail?, linkWarning: String? = nil, onSent: @escaping (String) -> Void) {
        self.invoice = invoice
        self.existing = existing
        self.linkWarning = linkWarning
        self.onSent = onSent
        let stored = (existing?.files ?? []).sorted { $0.createdAt < $1.createdAt }.map(MailFileDraft.init)
        _files = State(initialValue: stored)
        if let existing {
            _recipient = State(initialValue: existing.recipient)
            _subject = State(initialValue: existing.subject)
            _bodyText = State(initialValue: existing.body)
            _templateName = State(initialValue: existing.templateName)
            _templatePick = State(initialValue: .current)
            _appliedSubject = State(initialValue: existing.subject)
            _appliedBody = State(initialValue: existing.body)
        } else {
            let subject = InvoiceMailMerge.subject(for: invoice)
            let body = InvoiceMailMerge.letter(for: invoice, reminder: false)
            _recipient = State(initialValue: InvoiceMailMerge.recipients(for: invoice).first ?? "")
            _subject = State(initialValue: subject)
            _bodyText = State(initialValue: body)
            _templateName = State(initialValue: InvoiceMailBuiltin.invoice.title)
            _templatePick = State(initialValue: .builtin(.invoice))
            _appliedSubject = State(initialValue: subject)
            _appliedBody = State(initialValue: body)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                    if let linkWarning, !linkWarning.isEmpty {
                        Text(linkWarning)
                            .font(.callout)
                            .foregroundStyle(StudioDesign.rose)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    fieldsCard
                    letterCard
                    attachmentCard
                }
                .padding(StudioDesign.Spacing.card)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .navigationTitle(existing == nil ? "Send Invoice" : "Invoice Email")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isSending)
                        .help("Close without sending")
                }
                ToolbarItem {
                    Button("Preview", systemImage: "eye") { showingPreview = true }
                        .disabled(isSending || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Preview this letter")
                }
                ToolbarItem {
                    Button(existing?.state == .sent ? "Save" : "Save Draft", action: saveDraft)
                        .disabled(isSending)
                        .help(existing?.state == .sent ? "Save this letter" : "Save this letter without sending")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing?.state == .sent ? "Send Again" : "Send", systemImage: "paperplane") {
                        Task { await send() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending || !canSend)
                    .help(existing?.state == .sent ? "Send this invoice again" : "Send this invoice")
                }
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        .mailFileImporter(isPresented: $importingFiles, files: $files, error: $fileError)
        .sheet(isPresented: $showingPreview) {
            QuoteEmailPreview(
                recipient: recipient,
                subject: InvoiceMailMerge.fill(subject, invoice: invoice),
                bodyText: InvoiceMailMerge.fill(bodyText, invoice: invoice),
                payURL: InvoiceMailMerge.payURL(for: invoice),
                payPhrase: InvoiceMailMerge.payLinkPhrase,
                documentTitle: "Invoice PDF",
                extraNames: files.map(\.fileName)
            )
        }
        .onChange(of: templatePick) { previous, next in
            guard !suppressPick else {
                suppressPick = false
                return
            }
            guard next != .current else { return }
            if bodyText != appliedBody || subject != appliedSubject {
                pendingPick = next
                suppressPick = true
                templatePick = previous
                confirmReplace = true
                return
            }
            apply(next)
        }
        .confirmationDialog("Replace this letter?", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Replace") {
                if let pendingPick {
                    suppressPick = true
                    templatePick = pendingPick
                    apply(pendingPick)
                }
            }
            .help("Replace the letter with this template")
            Button("Cancel", role: .cancel) { pendingPick = nil }
                .help("Keep the letter you typed")
        } message: {
            Text("The note you typed will be replaced with the template.")
        }
        .confirmationDialog("Delete this template?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteTemplate)
                .help("Delete this template")
            Button("Cancel", role: .cancel) {}
                .help("Keep this template")
        }
        .alert("Save template", isPresented: $savingTemplate) {
            TextField("Name", text: $templateTitle)
            Button("Save", action: saveTemplate)
                .help("Save this template")
            Button("Cancel", role: .cancel) {}
                .help("Don’t save a template")
        } message: {
            Text("Names, the invoice number, the balance, and the pay link are stored as variables, so the next invoice fills them in.")
        }
        .alert("Couldn’t send", isPresented: sendErrorPresented) {
            Button("OK", role: .cancel) {}
                .help("Dismiss")
        } message: {
            Text(sendError ?? "")
        }
    }

    private var canSend: Bool {
        let to = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        return to.contains("@") && to.contains(".")
            && !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioLabeledStack {
                StudioLabeledRow("To") {
                    TextField("Client email", text: $recipient)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                }
                StudioLabeledRow("Subject") {
                    TextField("Subject", text: $subject)
                        .textFieldStyle(.roundedBorder)
                }
                StudioLabeledRow("Template") {
                    Picker("Template", selection: $templatePick) {
                        if existing != nil {
                            Text(templateName.isEmpty ? "This letter" : templateName).tag(InvoiceMailPick.current)
                        }
                        ForEach(InvoiceMailBuiltin.allCases) { builtin in
                            Text(builtin.title).tag(InvoiceMailPick.builtin(builtin))
                        }
                        if !templates.isEmpty {
                            Divider()
                            ForEach(templates) { template in
                                Text(template.name).tag(InvoiceMailPick.saved(template.persistentModelID))
                            }
                        }
                    }
                    .labelsHidden()
                }
            }
            Text(InvoiceMailMerge.tokenHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Save as Template", action: { templateTitle = ""; savingTemplate = true })
                    .help("Save this letter as a reusable template")
                if case .saved = templatePick {
                    Button("Delete Template", role: .destructive) { confirmDelete = true }
                        .help("Delete this template")
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var letterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Note")
                    .font(.headline)
                Spacer()
                Menu("All variables", systemImage: "plus") {
                    ForEach(AgreementVariableCatalog.groups) { group in
                        Section(group.title) {
                            ForEach(group.variables) { variable in
                                Button(variable.label) { insertVariable(variable.token) }
                            }
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Insert any agreement variable")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(InvoiceMailMerge.letterVariables) { variable in
                        Button {
                            insertVariable(variable.token)
                        } label: {
                            Text(variable.label)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(AgreementChipStyle.model.fill, in: Capsule())
                                .foregroundStyle(AgreementChipStyle.model.ink)
                        }
                        .buttonStyle(.plain)
                        .help(variable.token)
                    }
                }
            }
            .scrollIndicators(.hidden)
            QuoteLetterEditor(text: $bodyText, insertion: letterInsertion)
                .frame(minHeight: 280)
                .padding(8)
                .background(StudioDesign.Surface.paper.opacity(0.45), in: .rect(cornerRadius: 12))
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var attachmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Attachments", systemImage: "paperclip")
                .font(.headline)
            Label("Invoice PDF", systemImage: "doc.richtext")
                .font(.callout)
            MailFilesEditor(files: $files) { importingFiles = true }
            StudioLabeledStack {
                StudioLabeledRow("Pay link") {
                    Text(payLinkLine)
                        .textSelection(.enabled)
                        .font(.callout)
                }
            }
            Text("The invoice PDF always goes with the letter. Added files go with it. The pay link is in the letter.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var payLinkLine: String {
        let url = InvoiceMailMerge.payURL(for: invoice)
        if !url.isEmpty { return url }
        return invoice.balance > 0 ? "Created when you send, if this invoice has a balance." : "No balance due."
    }

    private var sendErrorPresented: Binding<Bool> {
        Binding(get: { sendError != nil }, set: { if !$0 { sendError = nil } })
    }

    private func apply(_ pick: InvoiceMailPick) {
        switch pick {
        case .current:
            return
        case .builtin(let builtin):
            subject = InvoiceMailMerge.subject(for: invoice)
            bodyText = InvoiceMailMerge.letter(for: invoice, reminder: builtin == .reminder)
            templateName = builtin.title
        case .saved(let id):
            guard let template = templates.first(where: { $0.persistentModelID == id }) else { return }
            let filled = InvoiceMailMerge.apply(template: template, to: invoice)
            subject = filled.subject
            bodyText = filled.body
            templateName = template.name
        }
        appliedSubject = subject
        appliedBody = bodyText
    }

    private func insertVariable(_ token: String) {
        let filled = InvoiceMailMerge.fill(token, invoice: invoice)
        letterInsertion = QuoteLetterInsertion(text: filled.isEmpty ? token : filled)
    }

    private func saveTemplate() {
        let name = templateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let subjectTemplate = InvoiceMailMerge.templatize(subject, invoice: invoice)
        let bodyTemplate = InvoiceMailMerge.templatize(bodyText, invoice: invoice)
        if let existing = templates.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            existing.subject = subjectTemplate
            existing.body = bodyTemplate
            existing.updatedAt = .now
            suppressPick = true
            templatePick = .saved(existing.persistentModelID)
        } else {
            let created = EmailTemplate(name: name, subject: subjectTemplate, body: bodyTemplate)
            modelContext.insert(created)
            try? modelContext.save()
            suppressPick = true
            templatePick = .saved(created.persistentModelID)
        }
        templateName = name
        try? modelContext.save()
    }

    private func deleteTemplate() {
        guard case .saved(let id) = templatePick,
              let template = templates.first(where: { $0.persistentModelID == id }) else { return }
        modelContext.delete(template)
        try? modelContext.save()
        suppressPick = true
        templatePick = .builtin(.invoice)
        apply(.builtin(.invoice))
    }

    private func saveDraft() {
        let record = storedLetter(sent: false, messageID: existing?.postmarkMessageID ?? "")
        if existing?.state == .sent {
            record.state = .sent
            record.sentAt = existing?.sentAt
        }
        try? modelContext.save()
        dismiss()
    }

    private func send() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        if invoice.balance > 0 {
            let links = PayLinkModel()
            await links.publish(
                invoice,
                in: modelContext,
                announce: false,
                clientEmail: recipient
            )
            if invoice.payToken.isEmpty {
                sendError = links.message.isEmpty ? "Couldn’t create the pay link." : links.message
                return
            }
        }
        subject = InvoiceMailMerge.fill(subject, invoice: invoice)
        bodyText = InvoiceMailMerge.ensuringPayLink(bodyText, invoice: invoice)
        let to = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyTo = invoice.studio?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let result = await InvoiceMailDelivery.send(
            invoice: invoice,
            recipient: to,
            replyTo: replyTo,
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            body: bodyText,
            extras: files
        )
        guard result.didLeaveTheMac else {
            sendError = result.note
            return
        }
        let record = storedLetter(sent: true, messageID: result.messageID)
        record.sentAt = .now
        record.payURL = InvoiceMailMerge.payURL(for: invoice)
        if invoice.status == .draft {
            invoice.status = .pending
            InvoiceMath.applyDerivedStatus(invoice)
            BooksTrail.noteMarkedSent(invoice, in: modelContext)
        }
        do {
            try modelContext.save()
        } catch {
            sendError = error.localizedDescription
            return
        }
        onSent(result.note)
        dismiss()
    }

    @discardableResult
    private func storedLetter(sent: Bool, messageID: String) -> InvoiceEmail {
        let record = existing ?? InvoiceEmail(invoiceKey: InvoiceMailKey.ensure(for: invoice))
        if existing == nil {
            modelContext.insert(record)
        }
        record.invoiceKey = InvoiceMailKey.ensure(for: invoice)
        record.recipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        record.subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        record.body = bodyText
        record.templateName = templateName
        record.payURL = InvoiceMailMerge.payURL(for: invoice)
        record.updatedAt = .now
        record.postmarkMessageID = messageID
        if sent {
            record.state = .sent
        } else if record.state != .sent {
            record.state = .draft
        }
        MailAttachmentSync.apply(files, quote: nil, invoice: record, in: modelContext)
        return record
    }
}
