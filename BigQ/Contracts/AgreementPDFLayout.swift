import AppKit
import Foundation

enum AgreementPDFLayout {
    enum Block: Equatable {
        case centeredHeadline(String)
        case horizontalRule
        case centeredSubhead(String)
        case field(label: String, value: String)
        case paragraph(String)
    }

    static func blocks(
        mergedHTML: String,
        agreementTitle: String,
        studioName: String?
    ) -> [Block] {
        let title = agreementTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let studio = studioName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lines = ContractDocument.plainLines(mergedHTML)
        var result: [Block] = []
        var index = 0
        var sawHeadline = false

        while index < lines.count {
            let line = lines[index]

            if let field = takeField(from: lines, index: &index, title: title) {
                result.append(.field(label: field.label, value: field.value))
                continue
            }

            if !sawHeadline, matchesHeadline(line, title: title) {
                result.append(.centeredHeadline(displayHeadline(AgreementInlineStyle.stripped(line), title: title)))
                result.append(.horizontalRule)
                sawHeadline = true
                index += 1
                continue
            }
            if matchesHeadline(line, title: title) {
                index += 1
                continue
            }
            if !studio.isEmpty,
               AgreementInlineStyle.stripped(line).caseInsensitiveCompare(studio) == .orderedSame {
                result.append(.centeredSubhead(studio))
                index += 1
                continue
            }
            if looksLikeStudioLine(line) {
                result.append(.centeredSubhead(AgreementInlineStyle.stripped(line)))
                index += 1
                continue
            }

            // One visual paragraph — do not glue the next form value / clause onto it.
            result.append(.paragraph(line))
            index += 1
        }

        if !sawHeadline, !title.isEmpty {
            result.insert(.centeredHeadline(title), at: 0)
            result.insert(.horizontalRule, at: 1)
        }
        return result
    }

    /// `Label: value` on one line, or `Label:` plus the following value line(s).
    static func takeField(
        from lines: [String],
        index: inout Int,
        title: String = ""
    ) -> (label: String, value: String)? {
        guard index < lines.count,
              let parsed = parseFieldLine(lines[index]) else { return nil }

        let start = index
        var value = parsed.value
        index += 1

        if AgreementInlineStyle.stripped(value).trimmingCharacters(in: .whitespaces).isEmpty {
            value = ""
            guard index < lines.count else {
                index = start
                return nil
            }
            let next = lines[index]
            if parseFieldLine(next) != nil
                || matchesHeadline(next, title: title)
                || looksLikeStudioLine(next)
                || looksLikeProse(next) {
                // Bare legal header (`COPYRIGHTS:`) or nothing to pair — not a form field.
                index = start
                return nil
            }
            value = next
            index += 1
        }

        while index < lines.count, isPaymentContinuation(lines[index]) {
            value += "\n" + lines[index]
            index += 1
        }

        // Only reject the *first* value line as prose — Pay Details stacks are long on purpose.
        let plainValue = AgreementInlineStyle.stripped(value)
        let firstValueLine = plainValue.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? plainValue
        if looksLikeProse(firstValueLine) {
            index = start
            return nil
        }
        return (parsed.label, value)
    }

    static func colonColumn(for labels: [String], font: NSFont, margin: CGFloat) -> (colonX: CGFloat, labelWidth: CGFloat) {
        let widths = labels.map { measure("\($0):", font: font) }
        let labelWidth = ceil(widths.max() ?? 72)
        return (margin + labelWidth, labelWidth)
    }

    static func measure(_ text: String, font: NSFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    /// Field rows like `Pay Details: …` — not payment continuations or prose with a colon.
    static func fieldLabel(in line: String) -> String? {
        parseFieldLine(line)?.label
    }

    static func parseField(_ line: String) -> (label: String, value: String)? {
        parseFieldLine(line)
    }

    static func isPaymentContinuation(_ line: String) -> Bool {
        let trimmed = AgreementInlineStyle.stripped(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // A real `Label: value` row is never a continuation — even if the value
        // mentions "due at signing".
        if parseFieldLine(trimmed) != nil { return false }
        let lower = trimmed.lowercased()
        if lower.contains("days prior") || lower.contains("day prior") { return true }
        if lower.hasPrefix("remaining balance") { return true }
        if lower.contains("due at signing") { return true }
        if trimmed.range(of: #"^\d{1,2}/\d{1,2}"#, options: .regularExpression) != nil { return true }
        // Amount-first continuations: `25%, 90 days prior…`
        if trimmed.range(of: #"^\d+%"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func parseFieldLine(_ line: String) -> (label: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        // Label is always plain (auto-bold); value keeps user style markers.
        let label = AgreementInlineStyle.stripped(String(trimmed[..<colon])).trimmingCharacters(in: .whitespaces)
        let styledValue = AgreementInlineStyle.trimmed(String(trimmed[trimmed.index(after: colon)...]))
        let value = AgreementInlineStyle.stripped(styledValue)
        guard !label.isEmpty, label.count <= 40 else { return nil }
        let lower = label.lowercased()
        // Payment-schedule continuations under Pay Details — not labels.
        if lower.contains("days prior") || lower.contains("day prior") { return nil }
        if lower.hasPrefix("remaining balance") { return nil }
        if label.range(of: #"^\d{1,2}/\d{1,2}"#, options: .regularExpression) != nil { return nil }
        if lower.hasPrefix("%") || label.range(of: #"^\d+%"#, options: .regularExpression) != nil {
            return nil
        }
        // Legal clause headers: "ENTIRE AGREEMENT:", "COPYRIGHTS:", …
        let letters = label.filter(\.isLetter)
        if letters.count >= 4, letters.allSatisfy(\.isUppercase) { return nil }
        // Long prose after the colon is a clause body, not a form value.
        if value.count > 60 { return nil }
        if looksLikeProse(value) { return nil }
        return (label, styledValue)
    }

    static func looksLikeProse(_ text: String) -> Bool {
        let trimmed = AgreementInlineStyle.stripped(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.count > 60 { return true }
        let lower = trimmed.lowercased()
        return lower.contains(" this agreement")
            || lower.hasPrefix("this agreement")
            || lower.contains("hereby")
            || lower.contains("contains the entire")
            || lower.contains("shall ")
            || lower.contains("parties ")
    }

    private static func matchesHeadline(_ line: String, title: String) -> Bool {
        let trimmed = AgreementInlineStyle.stripped(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        return trimmed.caseInsensitiveCompare(title) == .orderedSame
    }

    private static func displayHeadline(_ line: String, title: String) -> String {
        title.isEmpty ? line : title
    }

    private static func looksLikeStudioLine(_ line: String) -> Bool {
        let trimmed = AgreementInlineStyle.stripped(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 80, !trimmed.contains(":") else { return false }
        let lower = trimmed.lowercased()
        return lower.contains("photographer")
            || lower.contains("photography")
            || lower.contains(", llc")
            || lower.contains(" llc")
    }
}

extension ContractDocument {
    /// One line per block tag — single newlines between rows (no blank spacer lines).
    static func plainLines(_ html: String) -> [String] {
        // NSTextView.string is already plain — skip the HTML-strip regex gauntlet
        // (that alone hitchs long wedding agreements on Save flush).
        let source = html.contains("<") ? plain(html) : html
        return source.components(separatedBy: "\n").map {
            AgreementFieldTable.cleanLine($0)
        }.filter { !$0.isEmpty }
    }
}
