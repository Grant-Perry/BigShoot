import AppKit
import Foundation
import SwiftUI

/// User bold / italic / underline inside agreement text.
///
/// Stored HTML uses plain `<b>`, `<i>`, `<u>` tags. While the text moves through the
/// line-based pipeline (`plainLines` → field/paragraph parsing) those tags travel as
/// private-use marker characters so tag stripping and colon parsing never eat them.
/// Every display path (editor, detail view, PDF) renders markers via `attributed(_:…)`
/// and every structural check uses `stripped(_:)`.
enum AgreementInlineStyle {
    nonisolated struct Traits: OptionSet, Hashable, Sendable {
        let rawValue: Int
        static let bold = Traits(rawValue: 1)
        static let italic = Traits(rawValue: 2)
        static let underline = Traits(rawValue: 4)
    }

    static let boldOpen: Character = "\u{E000}"
    static let boldClose: Character = "\u{E001}"
    static let italicOpen: Character = "\u{E002}"
    static let italicClose: Character = "\u{E003}"
    static let underlineOpen: Character = "\u{E004}"
    static let underlineClose: Character = "\u{E005}"

    private static let markers: Set<Character> = [
        boldOpen, boldClose, italicOpen, italicClose, underlineOpen, underlineClose,
    ]

    static func containsMarkers(_ text: String) -> Bool {
        text.contains { markers.contains($0) }
    }

    /// Text with every style marker removed — for parsing, measuring, and headlines.
    static func stripped(_ text: String) -> String {
        guard containsMarkers(text) else { return text }
        return String(text.filter { !markers.contains($0) })
    }

    /// Drops markers that close before / open after the visible text (e.g. `**Label:** value`
    /// leaves a stray close on the value), then trims whitespace.
    static func trimmed(_ text: String) -> String {
        guard containsMarkers(text) else { return text.trimmingCharacters(in: .whitespaces) }
        let closers: Set<Character> = [boldClose, italicClose, underlineClose]
        let openers: Set<Character> = [boldOpen, italicOpen, underlineOpen]
        var chars = Array(text)
        while let first = chars.first, first.isWhitespace || closers.contains(first) {
            chars.removeFirst()
        }
        while let last = chars.last, last.isWhitespace || openers.contains(last) {
            chars.removeLast()
        }
        return String(chars)
    }

    // MARK: - HTML ⇄ markers

    /// `<b>`/`<strong>`, `<i>`/`<em>`, `<u>` (open + close) → markers. Run before generic tag stripping.
    static func markersFromHTMLTags(_ html: String) -> String {
        guard html.contains("<") else { return html }
        let rules: [(String, Character)] = [
            (#"(?i)<(b|strong)(\s[^>]*)?>"#, boldOpen),
            (#"(?i)</(b|strong)\s*>"#, boldClose),
            (#"(?i)<(i|em)(\s[^>]*)?>"#, italicOpen),
            (#"(?i)</(i|em)\s*>"#, italicClose),
            (#"(?i)<u(\s[^>]*)?>"#, underlineOpen),
            (#"(?i)</u\s*>"#, underlineClose),
        ]
        var result = html
        for (pattern, marker) in rules {
            result = result.replacingOccurrences(
                of: pattern,
                with: String(marker),
                options: .regularExpression
            )
        }
        return result
    }

    /// Markers → `<b>`/`<i>`/`<u>`. Call AFTER HTML-escaping the text.
    static func htmlTags(fromMarkers text: String) -> String {
        guard containsMarkers(text) else { return text }
        var out = ""
        out.reserveCapacity(text.count + 16)
        for character in text {
            switch character {
            case boldOpen: out += "<b>"
            case boldClose: out += "</b>"
            case italicOpen: out += "<i>"
            case italicClose: out += "</i>"
            case underlineOpen: out += "<u>"
            case underlineClose: out += "</u>"
            default: out.append(character)
            }
        }
        return out
    }

    // MARK: - Splitting

    /// Splits on newlines / U+2028 and re-balances markers so each line renders on its own.
    static func lines(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
        guard containsMarkers(normalized) else {
            return normalized.components(separatedBy: "\n")
        }
        var result: [String] = []
        var current = ""
        var active: Traits = []
        for character in normalized {
            if character == "\n" {
                current += closing(active)
                result.append(current)
                current = opening(active)
                continue
            }
            current.append(character)
            active = apply(character, to: active)
        }
        result.append(current)
        return result
    }

    // MARK: - Rendering

    /// Attributed text with markers applied on top of `font`. Markers never reach the output.
    @MainActor
    static func attributed(
        _ text: String,
        font: NSFont,
        attributes: [NSAttributedString.Key: Any] = [:]
    ) -> NSAttributedString {
        var base = attributes
        base[.font] = font
        guard containsMarkers(text) else {
            return NSAttributedString(string: text, attributes: base)
        }
        let result = NSMutableAttributedString()
        var active: Traits = []
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            var attrs = base
            attrs[.font] = styledFont(font, traits: active)
            if active.contains(.underline) {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            result.append(NSAttributedString(string: run, attributes: attrs))
            run = ""
        }
        for character in text {
            if markers.contains(character) {
                flush()
                active = apply(character, to: active)
            } else {
                run.append(character)
            }
        }
        flush()
        return result
    }

    /// SwiftUI flavor for `AgreementDocumentView`.
    static func attributedString(_ text: String) -> AttributedString {
        guard containsMarkers(text) else { return AttributedString(text) }
        var result = AttributedString()
        var active: Traits = []
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            var intents: InlinePresentationIntent = []
            if active.contains(.bold) { intents.insert(.stronglyEmphasized) }
            if active.contains(.italic) { intents.insert(.emphasized) }
            if !intents.isEmpty { piece.inlinePresentationIntent = intents }
            if active.contains(.underline) { piece.swiftUI.underlineStyle = .single }
            result += piece
            run = ""
        }
        for character in text {
            if markers.contains(character) {
                flush()
                active = apply(character, to: active)
            } else {
                run.append(character)
            }
        }
        flush()
        return result
    }

    // MARK: - Editor → markers

    /// Plain text of the editor with markers around user bold / italic / underline.
    /// Bold on field labels (`Client Name:`) and the agreement headline is automatic
    /// layout, not user styling, so it is skipped.
    @MainActor
    static func markedText(from storage: NSTextStorage, agreementTitle: String) -> String {
        let string = storage.string as NSString
        guard string.length > 0 else { return "" }
        let title = agreementTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = ""
        var location = 0
        while location < string.length {
            var start = 0, end = 0, contentsEnd = 0
            string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let lineRange = NSRange(location: start, length: contentsEnd - start)
            let line = string.substring(with: lineRange)
            out += markedLine(line, range: lineRange, storage: storage, title: title)
            if end > contentsEnd { out += "\n" }
            location = max(end, location + 1)
        }
        return out
    }

    @MainActor
    private static func markedLine(
        _ line: String,
        range: NSRange,
        storage: NSTextStorage,
        title: String
    ) -> String {
        guard range.length > 0 else { return line }
        let cleaned = AgreementFieldTable.cleanLine(line)
        let isHeadline = AgreementFieldTable.isHeadline(cleaned, title: title)
        // Offset (within the line) up to which bold is automatic: whole headline, or label through colon.
        var autoBoldEnd = 0
        if isHeadline {
            autoBoldEnd = range.length
        } else if AgreementPDFLayout.fieldLabel(in: line) != nil,
                  let colon = (line as NSString).range(of: ":").toOptional {
            autoBoldEnd = colon.location + colon.length
        }

        var out = ""
        var active: Traits = []
        storage.enumerateAttributes(in: range, options: []) { attrs, runRange, _ in
            let text = (storage.string as NSString).substring(with: runRange)
            var wanted: Traits = []
            if let font = attrs[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                if traits.contains(.boldFontMask) { wanted.insert(.bold) }
                if traits.contains(.italicFontMask) { wanted.insert(.italic) }
            }
            if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                wanted.insert(.underline)
            }
            let runStart = runRange.location - range.location
            let runEnd = runStart + runRange.length
            if wanted.contains(.bold), runStart < autoBoldEnd {
                if runEnd <= autoBoldEnd {
                    wanted.remove(.bold)
                } else {
                    // Run straddles the label colon — split it.
                    let split = autoBoldEnd - runStart
                    let head = (text as NSString).substring(to: split)
                    let tail = (text as NSString).substring(from: split)
                    var headTraits = wanted
                    headTraits.remove(.bold)
                    out += transition(from: active, to: headTraits) + head
                    out += transition(from: headTraits, to: wanted) + tail
                    active = wanted
                    return
                }
            }
            out += transition(from: active, to: wanted) + text
            active = wanted
        }
        out += closing(active)
        return out
    }

    // MARK: - Helpers

    private static func apply(_ marker: Character, to traits: Traits) -> Traits {
        var next = traits
        switch marker {
        case boldOpen: next.insert(.bold)
        case boldClose: next.remove(.bold)
        case italicOpen: next.insert(.italic)
        case italicClose: next.remove(.italic)
        case underlineOpen: next.insert(.underline)
        case underlineClose: next.remove(.underline)
        default: break
        }
        return next
    }

    private static func transition(from old: Traits, to new: Traits) -> String {
        guard old != new else { return "" }
        return closing(old.subtracting(new)) + opening(new.subtracting(old))
    }

    private static func opening(_ traits: Traits) -> String {
        var out = ""
        if traits.contains(.bold) { out.append(boldOpen) }
        if traits.contains(.italic) { out.append(italicOpen) }
        if traits.contains(.underline) { out.append(underlineOpen) }
        return out
    }

    private static func closing(_ traits: Traits) -> String {
        var out = ""
        if traits.contains(.underline) { out.append(underlineClose) }
        if traits.contains(.italic) { out.append(italicClose) }
        if traits.contains(.bold) { out.append(boldClose) }
        return out
    }

    @MainActor
    private static func styledFont(_ font: NSFont, traits: Traits) -> NSFont {
        var mask: NSFontTraitMask = []
        if traits.contains(.bold) { mask.insert(.boldFontMask) }
        if traits.contains(.italic) { mask.insert(.italicFontMask) }
        guard !mask.isEmpty else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: mask)
    }
}

private extension NSRange {
    var toOptional: NSRange? { location == NSNotFound ? nil : self }
}
