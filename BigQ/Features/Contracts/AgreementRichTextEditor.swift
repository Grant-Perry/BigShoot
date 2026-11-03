import AppKit
import SwiftUI

/// Rich text agreement body. The session owns inserts; this view only hosts the text view.
struct AgreementRichTextEditor: NSViewRepresentable {
    var session: AgreementEditorSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.usesRuler = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = AgreementRichTextEditing.bodyFont()
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.typingAttributes = [
            .font: AgreementRichTextEditing.bodyFont(),
            .foregroundColor: NSColor.labelColor,
        ]
        context.coordinator.attach(textView)
        // Defer the heavy HTML→attributed parse until after makeNSView returns so the
        // edit sheet can finish presenting before a long agreement is laid out.
        let initialHTML = session.html
        let initialTitle = session.agreementTitle
        context.coordinator.isHydrating = true
        Task { @MainActor in
            await Task.yield()
            guard context.coordinator.session.textView === textView else { return }
            let html = context.coordinator.session.html.isEmpty
                ? initialHTML
                : context.coordinator.session.html
            let title = context.coordinator.session.agreementTitle.isEmpty
                ? initialTitle
                : context.coordinator.session.agreementTitle
            AgreementRichTextEditing.load(
                html: html,
                into: textView,
                agreementTitle: title
            )
            context.coordinator.isHydrating = false
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.session = session
        context.coordinator.attach(textView)
        // Document swaps (new template selected) come through replaceDocument on the session.
        // Typing never reloads from here — that was the beachball.
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var session: AgreementEditorSession
        /// True while the initial deferred load is in flight — ignore publish noise.
        var isHydrating = false

        init(session: AgreementEditorSession) {
            self.session = session
        }

        func attach(_ textView: NSTextView) {
            session.textView = textView
        }

        func textDidBeginEditing(_ notification: Notification) {}

        func textDidEndEditing(_ notification: Notification) {
            // Commit HTML once on blur — but never synchronously. Save/Preview already
            // defer past resign; a sync highlight+normalize here collides with those
            // buttons and beachballs long wedding agreements.
            guard !isHydrating,
                  let textView = notification.object as? NSTextView else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                // Sheet may have dismissed (Save/Cancel) — do not touch a dying text view.
                guard !isHydrating,
                      session.textView === textView,
                      session.onCommit != nil else { return }
                // Chips are already painted on load/insert — skip the full-doc walk.
                session.commitFromTextView()
            }
        }

        func textDidChange(_ notification: Notification) {
            // Intentionally empty. Any highlight / HTML publish / Observable write
            // during typing rebuilds the quote sheet and beachballs long agreements.
            // The NSTextView is the source of truth until blur / Save / Preview flush.
        }
    }
}
