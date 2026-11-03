import AppKit
import Foundation
import Observation

/// Owns the agreement draft while editing. Inserts hit the text view directly —
/// never bounce through a SwiftUI `pendingInsert` binding (that beachballs).
@MainActor
@Observable
final class AgreementEditorSession {
    /// Live HTML mirror. ObservationIgnored on purpose — publishing this on every
    /// keystroke rebuilds the quote sheet under NSTextView and beachballs.
    @ObservationIgnored
    var html: String
    /// Weak handle registered by the representable. Insert uses this when present.
    @ObservationIgnored
    weak var textView: NSTextView?
    /// Optional sync into the SwiftUI `@Binding` after blur / insert / flush.
    @ObservationIgnored
    var onCommit: ((String) -> Void)?

    init(html: String = "") {
        self.html = html
    }

    /// Optional title used to place the rule under the agreement headline.
    var agreementTitle: String = ""

    func replaceDocument(with html: String) {
        self.html = html
        guard let textView else {
            onCommit?(html)
            return
        }
        AgreementRichTextEditing.load(
            html: html,
            into: textView,
            agreementTitle: agreementTitle
        )
        onCommit?(html)
    }

    /// Optional live-fill after the user leaves the text view (typed `[Field]` chips).
    @ObservationIgnored
    var polishAfterEdit: ((String) -> String)?

    func insertToken(_ token: String) {
        if let textView {
            AgreementRichTextEditing.insert(token, into: textView)
            commitFromTextView()
            return
        }
        html += token
        onCommit?(html)
    }

    /// Inserts already-resolved merge HTML (e.g. payment terms with `<br>` lines).
    func insertHTML(_ fragment: String) {
        if let textView {
            // Never alignFields here — that rebuilds the whole attributed document
            // and beachballs mid-click on a wedding agreement.
            AgreementRichTextEditing.insertHTML(fragment, into: textView)
            AgreementRichTextEditing.highlightTokens(in: textView, lightweight: true)
            commitFromTextView()
            return
        }
        html += fragment
        onCommit?(html)
    }

    func pullFromTextView() {
        guard let textView else { return }
        // Persist plain `Label: value` lines (not Cocoa HTML export) so reload
        // can rebuild the colon column instead of stacking label-above-value.
        html = AgreementFieldTable.normalizedHTML(
            from: textView.string,
            agreementTitle: agreementTitle
        )
    }

    /// Cheap Save path — no normalize, no SwiftUI publish.
    func pullRawPlainText() -> String {
        textView?.string ?? html
    }

    /// Empty the text storage + undo stack before SwiftUI destroys the representable.
    /// Tearing down a wedding-length attributed string on dismiss is a main-thread beachball.
    func gutForTeardown() {
        onCommit = nil
        guard let textView else { return }
        textView.delegate = nil
        textView.undoManager?.removeAllActions()
        if let storage = textView.textStorage, storage.length > 0 {
            storage.beginEditing()
            storage.setAttributedString(NSAttributedString(string: ""))
            storage.endEditing()
        }
        self.textView = nil
    }

    func commitFromTextView() {
        pullFromTextView()
        onCommit?(html)
    }

    func applyPolishAfterEditIfNeeded() {
        guard let polishAfterEdit else { return }
        pullFromTextView()
        let next = polishAfterEdit(html)
        guard next != html else { return }
        replaceDocument(with: next)
    }
}

/// Shared AppKit helpers for the agreement editor. Kept out of the representable
/// so the session can insert without going through `updateNSView`.
@MainActor
enum AgreementRichTextEditing {
    static func bodyFont(size: CGFloat = 15, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    private static func sansFont(matching current: NSFont, size: CGFloat) -> NSFont {
        let traits = NSFontManager.shared.traits(of: current)
        let bold = traits.contains(.boldFontMask)
        let italic = traits.contains(.italicFontMask)
        let weight: NSFont.Weight = bold ? .bold : .regular
        let base = bodyFont(size: size, weight: weight)
        guard italic else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    static func load(html: String, into textView: NSTextView, agreementTitle: String? = nil) {
        let attributed = AgreementFieldTable.attributedDocument(
            from: html,
            agreementTitle: agreementTitle
        )
        // Batch the swap so NSTextView does not ping-pong textDidChange mid-load.
        textView.textStorage?.beginEditing()
        textView.textStorage?.setAttributedString(attributed)
        textView.textStorage?.endEditing()
        textView.typingAttributes = [
            .font: bodyFont(),
            .foregroundColor: NSColor.labelColor,
        ]
        // Chip paint only. Full font/indent restyle on a wedding agreement beachballs —
        // attributedDocument already laid out fonts/field tabs.
        highlightTokens(in: textView, lightweight: true)
    }

    /// Shared HTML → attributed parse for fragments (chips / inserts).
    static func attributedDocument(from html: String) -> NSAttributedString {
        forceSans(attributed(from: html))
    }

    static func insert(_ token: String, into textView: NSTextView) {
        let selected = textView.selectedRange()
        let chip = tokenAttributes(token)
        textView.textStorage?.replaceCharacters(in: selected, with: chip)
        let cursor = selected.location + chip.length
        textView.setSelectedRange(NSRange(location: cursor, length: 0))
        textView.window?.makeFirstResponder(textView)
        // Token already painted via tokenAttributes — skip full-document walks.
    }

    static func insertHTML(_ fragment: String, into textView: NSTextView) {
        let selected = textView.selectedRange()
        let baseSize = ((textView.typingAttributes[.font] as? NSFont) ?? bodyFont()).pointSize
        let lines = termsLines(fromHTML: fragment)
        let insertion: NSAttributedString
        if lines.count > 1, looksLikePaymentTerms(lines) {
            // Multi-line terms stay in the value column via line separators.
            insertion = NSAttributedString(
                string: lines.joined(separator: "\u{2028}"),
                attributes: [
                    .font: bodyFont(size: baseSize),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
        } else {
            // Plain text only. NSAttributedString's HTML importer launches the out-of-process
            // nsattributedstringagent (WebKit) and blocks main until it answers — every chip
            // insert was a beachball. Merge values are plain text + <br>, so strip instead.
            insertion = NSAttributedString(
                string: plainFragment(fromHTML: fragment),
                attributes: [
                    .font: bodyFont(size: baseSize),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
        }
        textView.textStorage?.replaceCharacters(in: selected, with: insertion)
        let cursor = selected.location + insertion.length
        textView.setSelectedRange(NSRange(location: cursor, length: 0))
        textView.window?.makeFirstResponder(textView)
    }

    private static func termsLines(fromHTML fragment: String) -> [String] {
        fragment
            .replacingOccurrences(of: "&#8232;", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func plainFragment(fromHTML fragment: String) -> String {
        var text = fragment
            .replacingOccurrences(of: "&#8232;", with: "\u{2028}")
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</(p|div|li)>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&"),
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikePaymentTerms(_ lines: [String]) -> Bool {
        lines.contains {
            let lower = $0.lowercased()
            return lower.contains("due at signing")
                || lower.contains("days prior")
                || lower.contains("day prior")
                || lower.contains("remaining balance")
        }
    }

    static func html(from textView: NSTextView) -> String {
        guard let storage = textView.textStorage, storage.length > 0 else { return "" }
        let range = NSRange(location: 0, length: storage.length)
        guard let data = try? storage.data(
            from: range,
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]
        ), let html = String(data: data, encoding: .utf8) else {
            return storage.string
        }
        return html
    }

    /// - Parameter lightweight: Typing path — only repaint merge/Ask chips. Skips full-document
    ///   font remapping and paragraph walks that beachball on long wedding agreements.
    static func highlightTokens(in textView: NSTextView, lightweight: Bool = false) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }

        if !lightweight {
            storage.enumerateAttribute(.font, in: full) { value, range, _ in
                let current = (value as? NSFont) ?? bodyFont()
                let size = min(max(current.pointSize, 12), 28)
                let mapped = sansFont(matching: current, size: size)
                if mapped != current {
                    storage.addAttribute(.font, value: mapped, range: range)
                }
            }

            boldFieldLabels(in: storage)
            stripRogueIndents(in: storage)
        }

        storage.removeAttribute(.backgroundColor, range: full)
        if !lightweight {
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        }
        guard let regex = try? NSRegularExpression(pattern: AgreementVariableCatalog.tokenPattern) else { return }
        for match in regex.matches(in: storage.string, range: full) {
            let token = (storage.string as NSString).substring(with: match.range)
            let ask = AgreementAskField.isAskToken(token)
            storage.addAttribute(
                .backgroundColor,
                value: ask ? askBackground : chipBackground,
                range: match.range
            )
            storage.addAttribute(
                .foregroundColor,
                value: ask ? askForeground : chipForeground,
                range: match.range
            )
        }
    }

    /// Kill leftover field-column headIndent / tab stops on prose (e.g. ENTIRE AGREEMENT).
    private static func stripRogueIndents(in storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        storage.enumerateAttribute(.paragraphStyle, in: full, options: []) { value, range, _ in
            guard let existing = value as? NSParagraphStyle else { return }
            let paragraph = (storage.string as NSString).substring(with: range)
            let trimmed = AgreementFieldTable.cleanLine(paragraph)
            let isFieldRow = existing.tabStops.count >= 2
                && existing.tabStops.contains(where: { $0.alignment == .right })
            let isPayContinuation = AgreementPDFLayout.isPaymentContinuation(trimmed)
                && existing.headIndent > 0
            if isFieldRow || isPayContinuation { return }

            guard existing.headIndent != 0
                || existing.firstLineHeadIndent != 0
                || existing.tailIndent != 0
                || !existing.tabStops.isEmpty
            else { return }

            let style = existing.mutableCopy() as! NSMutableParagraphStyle
            style.headIndent = 0
            style.firstLineHeadIndent = 0
            style.tailIndent = 0
            style.tabStops = []
            style.defaultTabInterval = 0
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
    }

    /// Field labels stay the same point size as their values — bold only, no size bump.
    private static func boldFieldLabels(in storage: NSTextStorage) {
        let text = storage.string as NSString
        var lineStart = 0
        while lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            defer { lineStart = NSMaxRange(lineRange) }
            let rawLine = text.substring(with: lineRange)
            guard AgreementPDFLayout.fieldLabel(in: rawLine) != nil,
                  let colon = rawLine.firstIndex(of: ":") else { continue }

            let colonOffset = rawLine.distance(from: rawLine.startIndex, to: colon)
            var labelStart = lineRange.location
            let labelEnd = lineRange.location + colonOffset + 1 // include ":"
            while labelStart < labelEnd,
                  let scalar = UnicodeScalar(text.character(at: labelStart)),
                  CharacterSet.whitespacesAndNewlines.contains(scalar) {
                labelStart += 1
            }
            let labelRange = NSRange(location: labelStart, length: max(0, labelEnd - labelStart))
            guard labelRange.length > 0 else { continue }

            // Match the value’s size (or the label’s current size) — never invent a new one.
            let valueLocation = min(labelEnd, text.length - 1)
            let sizeSource = (storage.attribute(.font, at: max(valueLocation, 0), effectiveRange: nil) as? NSFont)
                ?? (storage.attribute(.font, at: labelStart, effectiveRange: nil) as? NSFont)
                ?? bodyFont()
            let size = min(max(sizeSource.pointSize, 12), 28)
            storage.addAttribute(.font, value: bodyFont(size: size, weight: .bold), range: labelRange)
        }
    }

    private static let chipBackground = NSColor(calibratedRed: 0.72, green: 0.88, blue: 0.96, alpha: 1)
    private static let chipForeground = NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.48, alpha: 1)
    private static let askBackground = NSColor(calibratedRed: 0.93, green: 0.82, blue: 0.55, alpha: 1)
    private static let askForeground = NSColor(calibratedRed: 0.42, green: 0.28, blue: 0.06, alpha: 1)

    private static func tokenAttributes(_ token: String) -> NSAttributedString {
        let ask = AgreementAskField.isAskToken(token)
        return NSAttributedString(string: token, attributes: [
            .font: bodyFont(),
            .foregroundColor: ask ? askForeground : chipForeground,
            .backgroundColor: ask ? askBackground : chipBackground,
        ])
    }

    private static func attributed(from html: String) -> NSAttributedString {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return NSAttributedString(string: "", attributes: [
                .font: bodyFont(),
                .foregroundColor: NSColor.labelColor,
            ])
        }
        let wrapped = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
          body { font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif; font-size: 15px; }
        </style></head><body>\(html)</body></html>
        """
        if let data = wrapped.data(using: .utf8) {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]
            if let parsed = try? NSAttributedString(data: data, options: options, documentAttributes: nil),
               !parsed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return forceSans(parsed)
            }
        }
        return NSAttributedString(string: html, attributes: [
            .font: bodyFont(),
            .foregroundColor: NSColor.labelColor,
        ])
    }

    private static func forceSans(
        _ source: NSAttributedString,
        uniformSize: CGFloat? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: result.length)
        guard full.length > 0 else { return result }
        result.enumerateAttribute(.font, in: full) { value, range, _ in
            let current = (value as? NSFont) ?? bodyFont()
            let size = uniformSize ?? min(max(current.pointSize, 12), 28)
            result.addAttribute(.font, value: sansFont(matching: current, size: size), range: range)
        }
        return result
    }
}
