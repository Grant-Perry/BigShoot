import AppKit
import Foundation

/// Field rows on one line each: right-aligned labels, shared colon column, values after.
/// Cocoa HTML `<table>` stacks cells vertically in NSTextView — tabs do not.
enum AgreementFieldTable {
    private static let valueGap: CGFloat = 10

    /// Full agreement body as attributed text (headline, rule, aligned fields, prose).
    @MainActor
    static func attributedDocument(
        from html: String,
        agreementTitle: String? = nil,
        fontSize: CGFloat = 15
    ) -> NSAttributedString {
        let lines = ContractDocument.plainLines(html)
        let result = NSMutableAttributedString()
        guard !lines.isEmpty else { return result }

        let title = agreementTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bodyFont = AgreementRichTextEditing.bodyFont(size: fontSize)
        let labelFont = AgreementRichTextEditing.bodyFont(size: fontSize, weight: .bold)
        let ink = NSColor.labelColor

        var index = 0
        var fieldRows: [(label: String, value: String)] = []
        var inFields = false
        var placedHeadline = false

        while index < lines.count {
            let line = Self.cleanLine(lines[index])

            if !placedHeadline, isHeadline(line, title: title) {
                flushFields(
                    &fieldRows,
                    inFields: &inFields,
                    into: result,
                    labelFont: labelFont,
                    valueFont: bodyFont,
                    color: ink
                )
                appendHeadline(
                    displayHeadline(AgreementInlineStyle.stripped(line), title: title),
                    into: result,
                    font: AgreementRichTextEditing.bodyFont(size: max(fontSize + 3, 18), weight: .bold),
                    color: ink
                )
                appendHorizontalRule(into: result, color: .secondaryLabelColor)
                placedHeadline = true
                index += 1
                continue
            }

            if let field = takeField(from: lines, index: &index, title: title) {
                inFields = true
                fieldRows.append(field)
                continue
            }

            flushFields(
                &fieldRows,
                inFields: &inFields,
                into: result,
                labelFont: labelFont,
                valueFont: bodyFont,
                color: ink
            )

            if looksLikeStudioLine(line) {
                appendCentered(line, into: result, font: bodyFont, color: ink)
            } else {
                // Legal headers / prose — never inherit field tab stops or headIndent.
                appendParagraph(line, into: result, font: bodyFont, color: ink)
            }
            index += 1
        }

        flushFields(
            &fieldRows,
            inFields: &inFields,
            into: result,
            labelFont: labelFont,
            valueFont: bodyFont,
            color: ink
        )

        if !placedHeadline, !title.isEmpty {
            let head = NSMutableAttributedString()
            appendHeadline(
                title,
                into: head,
                font: AgreementRichTextEditing.bodyFont(size: max(fontSize + 3, 18), weight: .bold),
                color: ink
            )
            appendHorizontalRule(into: head, color: .secondaryLabelColor)
            result.insert(head, at: 0)
        }

        return result
    }

    @MainActor
    private static func flushFields(
        _ rows: inout [(label: String, value: String)],
        inFields: inout Bool,
        into result: NSMutableAttributedString,
        labelFont: NSFont,
        valueFont: NSFont,
        color: NSColor
    ) {
        guard inFields, !rows.isEmpty else {
            rows = []
            inFields = false
            return
        }
        appendFields(rows, into: result, labelFont: labelFont, valueFont: valueFont, color: color)
        rows = []
        inFields = false
    }

    @MainActor
    static func alignFields(in storage: NSTextStorage, agreementTitle: String? = nil) {
        guard storage.length > 0 else { return }
        let rebuilt = attributedDocument(
            from: storage.string,
            agreementTitle: agreementTitle
        )
        storage.beginEditing()
        storage.setAttributedString(rebuilt)
        storage.endEditing()
    }

    /// HTML form used by tests / callers that still want markup.
    static func normalizedHTML(from html: String, agreementTitle: String? = nil) -> String {
        // Keep a lightweight HTML mirror for unit tests — editor uses attributedDocument.
        let lines = ContractDocument.plainLines(html)
        var parts: [String] = []
        var index = 0
        let title = agreementTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var placedRule = false
        while index < lines.count {
            let line = cleanLine(lines[index])
            if !placedRule, isHeadline(line, title: title) {
                parts.append("<p style=\"text-align:center;font-weight:700;\">\(escape(displayHeadline(AgreementInlineStyle.stripped(line), title: title)))</p>")
                parts.append("<hr>")
                placedRule = true
                index += 1
                continue
            }
            if AgreementPDFLayout.parseField(line) != nil {
                var rows: [(label: String, value: String)] = []
                while index < lines.count,
                      let field = takeField(from: lines, index: &index, title: title) {
                    rows.append(field)
                }
                // `Address:` with no value, followed by another field (`Email: …`), parses as a
                // field but takeField rejects it. Without this, index never advances → infinite loop.
                if rows.isEmpty {
                    parts.append("<p>\(styledEscape(line))</p>")
                    index += 1
                    continue
                }
                for row in rows {
                    let valueLines = AgreementInlineStyle.lines(row.value)
                        .map { AgreementInlineStyle.trimmed($0) }
                        .filter { !AgreementInlineStyle.stripped($0).isEmpty }
                    let first = valueLines.first ?? ""
                    parts.append("<p>\(escape(row.label)): \(styledEscape(first))</p>")
                    for cont in valueLines.dropFirst() {
                        parts.append("<p>\(styledEscape(cont))</p>")
                    }
                }
                continue
            }
            parts.append("<p>\(styledEscape(line))</p>")
            index += 1
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Field take / append

    private static func takeField(
        from lines: [String],
        index: inout Int,
        title: String
    ) -> (label: String, value: String)? {
        // Keep editor HTML and preview/PDF on the same pairing rules.
        AgreementPDFLayout.takeField(from: lines, index: &index, title: title)
    }

    /// Drop editor tab-stop residue so legal clauses never re-indent halfway across.
    static func cleanLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private static func appendFields(
        _ rows: [(label: String, value: String)],
        into result: NSMutableAttributedString,
        labelFont: NSFont,
        valueFont: NSFont,
        color: NSColor
    ) {
        let colonX = ceil(
            rows.map { AgreementPDFLayout.measure("\($0.label):", font: labelFont) }.max() ?? 72
        )
        let valueX = colonX + valueGap

        let rowStyle = NSMutableParagraphStyle()
        rowStyle.tabStops = [
            NSTextTab(textAlignment: .right, location: colonX, options: [:]),
            NSTextTab(textAlignment: .left, location: valueX, options: [:]),
        ]
        rowStyle.defaultTabInterval = 0
        rowStyle.firstLineHeadIndent = 0
        rowStyle.headIndent = 0
        rowStyle.paragraphSpacing = 2

        // Continuations (Pay Details lines 2…) start under the value column only.
        let contStyle = NSMutableParagraphStyle()
        contStyle.firstLineHeadIndent = valueX
        contStyle.headIndent = valueX
        contStyle.paragraphSpacing = 2

        for row in rows {
            let valueLines = AgreementInlineStyle.lines(row.value)
                .map { AgreementInlineStyle.trimmed($0) }
                .filter { !AgreementInlineStyle.stripped($0).isEmpty }

            let first = valueLines.first ?? ""
            let line = NSMutableAttributedString()
            // \tLabel:\tvalue — right tab pins the colon; left tab starts the value.
            line.append(NSAttributedString(string: "\t", attributes: [
                .font: labelFont, .foregroundColor: color, .paragraphStyle: rowStyle,
            ]))
            line.append(NSAttributedString(string: "\(row.label):", attributes: [
                .font: labelFont, .foregroundColor: color, .paragraphStyle: rowStyle,
            ]))
            line.append(NSAttributedString(string: "\t", attributes: [
                .font: valueFont, .foregroundColor: color, .paragraphStyle: rowStyle,
            ]))
            line.append(AgreementInlineStyle.attributed(first + "\n", font: valueFont, attributes: [
                .foregroundColor: color, .paragraphStyle: rowStyle,
            ]))
            result.append(line)

            for cont in valueLines.dropFirst() {
                result.append(AgreementInlineStyle.attributed(cont + "\n", font: valueFont, attributes: [
                    .foregroundColor: color, .paragraphStyle: contStyle,
                ]))
            }
        }
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: valueFont, .foregroundColor: color,
        ]))
    }

    @MainActor
    private static func appendHeadline(
        _ text: String,
        into result: NSMutableAttributedString,
        font: NSFont,
        color: NSColor
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacing = 2
        result.append(NSAttributedString(string: text + "\n", attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style,
        ]))
    }

    @MainActor
    private static func appendHorizontalRule(into result: NSMutableAttributedString, color: NSColor) {
        let block = NSTextBlock()
        block.setValue(10_000, type: .absoluteValueType, for: .width)
        block.setWidth(0, type: .absoluteValueType, for: .padding)
        block.setWidth(0, type: .absoluteValueType, for: .border)
        block.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
        block.setBorderColor(color)

        let style = NSMutableParagraphStyle()
        style.textBlocks = [block]
        style.paragraphSpacing = 10
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: AgreementRichTextEditing.bodyFont(size: 4),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]))
    }

    @MainActor
    private static func appendCentered(
        _ text: String,
        into result: NSMutableAttributedString,
        font: NSFont,
        color: NSColor
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacing = 6
        result.append(AgreementInlineStyle.attributed(text + "\n", font: font, attributes: [
            .foregroundColor: color, .paragraphStyle: style,
        ]))
    }

    @MainActor
    private static func appendParagraph(
        _ text: String,
        into result: NSMutableAttributedString,
        font: NSFont,
        color: NSColor
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        style.tabStops = []
        style.defaultTabInterval = 0
        style.paragraphSpacing = 10
        result.append(AgreementInlineStyle.attributed(text + "\n", font: font, attributes: [
            .foregroundColor: color, .paragraphStyle: style,
        ]))
    }

    static func isHeadline(_ line: String, title: String) -> Bool {
        let trimmed = AgreementInlineStyle.stripped(line).trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, trimmed.caseInsensitiveCompare(title) == .orderedSame {
            return true
        }
        let lower = trimmed.lowercased()
        return lower.hasSuffix(" agreement") || lower == "agreement"
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

    /// Escape, then turn style markers into `<b>` / `<i>` / `<u>`.
    private static func styledEscape(_ text: String) -> String {
        AgreementInlineStyle.htmlTags(fromMarkers: escape(text))
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
