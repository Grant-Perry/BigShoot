import AppKit
import SwiftUI

struct QuoteLetterInsertion: Identifiable {
    let id = UUID()
    var text: String
}

/// Plain letter editor with a little extra line spacing. Inserts land at the caret.
struct QuoteLetterEditor: NSViewRepresentable {
    @Binding var text: String
    var insertion: QuoteLetterInsertion?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.string = text
        applySpacing(textView)
        scroll.drawsBackground = false
        textView.setAccessibilityLabel("Note")
        context.coordinator.text = $text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        if let insertion, context.coordinator.lastInsertion != insertion.id {
            context.coordinator.lastInsertion = insertion.id
            insert(insertion.text, into: textView)
            return
        }
        guard textView.string != text else { return }
        let selected = textView.selectedRange()
        textView.string = text
        applySpacing(textView)
        let maxLocation = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selected.location, maxLocation), length: 0))
    }

    private func insert(_ value: String, into textView: NSTextView) {
        guard !value.isEmpty else { return }
        let focused = textView.window?.firstResponder === textView
        if focused {
            textView.insertText(value, replacementRange: textView.selectedRange())
            return
        }
        let existing = textView.string as NSString
        let end = existing.length
        let prefix = end == 0 || existing.hasSuffix("\n") ? "" : "\n"
        textView.insertText(prefix + value, replacementRange: NSRange(location: end, length: 0))
    }

    private func applySpacing(_ textView: NSTextView) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.defaultParagraphStyle = style
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let length = (textView.string as NSString).length
        guard length > 0 else { return }
        textView.textStorage?.addAttributes(
            [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
            ],
            range: NSRange(location: 0, length: length)
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>?
        var lastInsertion: UUID?

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let value = textView.string
            if text?.wrappedValue != value {
                text?.wrappedValue = value
            }
        }
    }
}
