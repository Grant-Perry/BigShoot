import SwiftData
import SwiftUI

/// Lets the parent sheet pull live NSTextView HTML before Save / Preview
/// (typing must not publish into SwiftUI — that beachballs).
@MainActor
final class AgreementEditFlush {
    var run: () -> Void = {}
    /// Pull HTML from the text view without publishing into the SwiftUI `@Binding`.
    var pull: () -> String = { "" }
    /// Plain `NSTextView.string` only — no normalize (Save hot path).
    var pullRaw: () -> String = { "" }
    /// Drop `onCommit` immediately so a deferred blur cannot publish mid-Save.
    var disarm: () -> Void = {}
    /// Empty text storage + undo before unmount/dismiss.
    var gut: () -> Void = {}
    func call() { run() }
    func pullHTML() -> String { pull() }
    func pullRawPlainText() -> String { pullRaw() }
    func disarmPublishing() { disarm() }
    func gutEditor() { gut() }
}

struct QuoteAgreementEditor: View {
    @Binding var title: String
    @Binding var html: String
    var templates: [Contract]
    var onApplyTemplate: (Contract, [String: String]) -> Void
    var onClear: () -> Void
    var onPreview: (() -> Void)?
    var flush: AgreementEditFlush?

    /// Clarifies where blue merge chips pull from (quote vs job).
    var mergeSourceLabel: String = "the quote"
    /// Optional pass after Ask answers — job contracts use this to fill client chips in-editor.
    var polishHTML: (String) -> String = { $0 }
    /// Minimum height for the rich-text + variables pane (default suits dedicated agreement sheets).
    var minEditorHeight: CGFloat = 280

    @State private var session: AgreementEditorSession
    @State private var showAskPrompt = false
    @State private var askInterview: AgreementAskInterview?
    /// Cached so body does not scan the full wedding agreement HTML every render.
    @State private var hasAskFields = false
    @State private var hasBody = false

    init(
        title: Binding<String>,
        html: Binding<String>,
        templates: [Contract],
        onApplyTemplate: @escaping (Contract, [String: String]) -> Void,
        onClear: @escaping () -> Void,
        onPreview: (() -> Void)? = nil,
        flush: AgreementEditFlush? = nil,
        mergeSourceLabel: String = "the quote",
        polishHTML: @escaping (String) -> String = { $0 },
        minEditorHeight: CGFloat = 280
    ) {
        _title = title
        _html = html
        self.templates = templates
        self.onApplyTemplate = onApplyTemplate
        self.onClear = onClear
        self.onPreview = onPreview
        self.flush = flush
        self.mergeSourceLabel = mergeSourceLabel
        self.polishHTML = polishHTML
        self.minEditorHeight = minEditorHeight
        let initial = html.wrappedValue
        _session = State(initialValue: AgreementEditorSession(html: initial))
        _hasBody = State(initialValue: !title.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !initial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        _hasAskFields = State(initialValue: AgreementAskField.hasUnresolvedAsks(in: initial))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Agreement")
                    .font(.headline)
                Spacer()
                if let onPreview, hasBody {
                    Button("Preview Contract", systemImage: "doc.richtext") {
                        // Resign finishes first; then pull HTML and hand off (sync flush
                        // during NSTextView resign beachballs).
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            flushSession()
                            onPreview()
                        }
                    }
                    .help("Preview the agreement with quote variables filled in")
                }
                if hasAskFields {
                    Button("Fill Ask Fields…") {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            flushSession()
                            presentAskInterview(prompts: AgreementAskField.prompts(in: session.html))
                        }
                    }
                }
                if !templates.isEmpty {
                    Menu("Use template") {
                        ForEach(templates) { template in
                            Button(template.displayTitle) {
                                beginApply(template)
                            }
                        }
                    }
                }
                if hasBody {
                    Button("Clear", role: .destructive) {
                        session.replaceDocument(with: "")
                        onClear()
                        refreshChromeFlags(from: "")
                    }
                }
            }
            TextField("Title", text: $title)
            Text("Blue fields fill from \(mergeSourceLabel) as soon as that data is known. Gold Ask fields are interview questions you answer here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    AgreementFormatBar()
                    Divider()
                    AgreementRichTextEditor(session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                AgreementVariableSidebar(
                    onInsert: insertVariable,
                    onAskField: { showAskPrompt = true }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: minEditorHeight)
            .studioCard(cornerRadius: 10)
        }
        .onAppear {
            session.agreementTitle = title
            session.polishAfterEdit = polishHTML
            let htmlBinding = $html
            session.onCommit = { next in
                if htmlBinding.wrappedValue != next {
                    htmlBinding.wrappedValue = next
                }
                // Flags update off the typing path (commit is blur / insert / flush only).
            }
            flush?.run = {
                session.commitFromTextView()
            }
            flush?.pull = {
                session.pullFromTextView()
                return session.html
            }
            flush?.pullRaw = {
                session.pullRawPlainText()
            }
            flush?.disarm = {
                session.onCommit = nil
            }
            flush?.gut = {
                session.gutForTeardown()
            }
            refreshChromeFlags(from: session.html)
        }
        .onChange(of: title) { _, new in
            session.agreementTitle = new
            refreshChromeFlags(from: session.html)
        }
        .onChange(of: html) { _, new in
            // External replace (template apply / Fill Client Fields). Skip no-ops.
            guard new != session.html else {
                refreshChromeFlags(from: new)
                return
            }
            // Avoid ContractDocument.plain() on both sides — that alone hitchs large agreements.
            session.replaceDocument(with: new)
            refreshChromeFlags(from: new)
        }
        .onDisappear {
            // Do not flush here — Save/Preview already pull HTML after a short defer.
            // Re-committing a wedding agreement while the NSTextView is tearing down
            // is a reliable beachball (Cancel and post-Save dismiss both hit this).
            session.onCommit = nil
            flush?.run = {}
            flush?.pull = { "" }
            flush?.pullRaw = { "" }
            flush?.disarm = {}
            flush?.gut = {}
        }
        .sheet(isPresented: $showAskPrompt) {
            AgreementAskPromptSheet { prompt in
                let token = AgreementAskField.token(prompt: prompt)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    session.insertToken(token)
                    refreshChromeFlags(from: session.html)
                }
            }
        }
        .sheet(item: $askInterview) { interview in
            AgreementAskAnswersSheet(prompts: interview.prompts) { answers in
                if let template = interview.pendingTemplate {
                    onApplyTemplate(template, answers)
                } else {
                    let next = polishHTML(AgreementAskField.apply(session.html, answers: answers))
                    html = next
                    session.replaceDocument(with: next)
                }
                refreshChromeFlags(from: session.html)
            }
        }
    }

    private func beginApply(_ template: Contract) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            flushSession()
            let prompts = AgreementAskField.prompts(in: template.html)
            if prompts.isEmpty {
                onApplyTemplate(template, [:])
                refreshChromeFlags(from: html)
                return
            }
            presentAskInterview(prompts: prompts, pendingTemplate: template)
        }
    }

    private func presentAskInterview(prompts: [String], pendingTemplate: Contract? = nil) {
        guard !prompts.isEmpty else { return }
        askInterview = AgreementAskInterview(prompts: prompts, pendingTemplate: pendingTemplate)
    }

    /// Sidebar chips resolve immediately when the quote already has that data.
    private func insertVariable(_ variable: AgreementVariable) {
        let resolved = polishHTML(variable.token)
        if resolved != variable.token,
           !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.insertHTML(resolved)
        } else {
            session.insertToken(variable.token)
        }
        refreshChromeFlags(from: session.html)
    }

    private func flushSession() {
        session.commitFromTextView()
        refreshChromeFlags(from: session.html)
    }

    private func refreshChromeFlags(from source: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = source.trimmingCharacters(in: .whitespacesAndNewlines)
        hasBody = !trimmedTitle.isEmpty || !trimmedBody.isEmpty
        hasAskFields = AgreementAskField.hasUnresolvedAsks(in: source)
    }
}

/// Carries Ask prompts into the interview sheet so SwiftUI cannot present an empty copy.
private struct AgreementAskInterview: Identifiable {
    let id = UUID()
    var prompts: [String]
    var pendingTemplate: Contract?
}
