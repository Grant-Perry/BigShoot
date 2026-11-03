import AppKit
import Foundation

enum ContractDocument {
    /// The agreement as readable type. ShootQ stored HTML, not a PDF.
    @MainActor
    static func rendered(_ html: String) -> AttributedString {
        let fallback = AttributedString(plain(html))
        guard hasReadableBody(html), let data = wrapped(html).data(using: .utf8) else {
            return fallback
        }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let parsed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return fallback
        }
        let laidOut = sans(parsed)
        let words = laidOut.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return fallback }
        return AttributedString(laidOut)
    }

    static func hasReadableBody(_ html: String) -> Bool {
        !plain(html).isEmpty
    }

    static func plain(_ html: String) -> String {
        var text = bodyContent(html)
        // Cocoa HTML Writer stores styles in <head>. Drop those blocks or the CSS becomes "words".
        text = text.replacingOccurrences(
            of: #"(?is)<style\b[^>]*>.*?</style>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?is)<script\b[^>]*>.*?</script>"#,
            with: " ",
            options: .regularExpression
        )
        // Keep user bold / italic / underline as markers before generic tag stripping.
        text = AgreementInlineStyle.markersFromHTMLTags(text)
        let breaks = ["</p>", "</div>", "</li>", "</h1>", "</h2>", "</h3>", "<br>", "<br/>", "<br />"]
        for tag in breaks {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        // Inline tags sit mid-sentence; a space here would detach trailing punctuation.
        text = text.replacingOccurrences(
            of: #"(?i)</?(span|a|font|small|big|sub|sup|mark)(\s[^>]*)?>"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'"
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        let lines = text.components(separatedBy: .newlines).map { line in
            line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Prefer the `<body>` when AppKit saved a full HTML document; otherwise use the fragment.
    private static func bodyContent(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<body\b[^>]*>(.*?)</body>"#
        ) else { return html }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let bodyRange = Range(match.range(at: 1), in: html) else {
            return html
        }
        return String(html[bodyRange])
    }

    private static func wrapped(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          body { font-family: "Helvetica Neue", sans-serif; font-size: 15px; color: #1c1c1e; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    @MainActor
    private static func sans(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: result.length)
        guard full.length > 0 else { return result }
        result.enumerateAttribute(.font, in: full) { value, range, _ in
            let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            let size = min(max(current.pointSize, 13), 22)
            let traits = NSFontManager.shared.traits(of: current)
                .intersection([.boldFontMask, .italicFontMask])
            let family = NSFont.systemFont(ofSize: size).familyName ?? "Helvetica Neue"
            let font = NSFontManager.shared.font(
                withFamily: family,
                traits: traits,
                weight: traits.contains(.boldFontMask) ? 9 : 5,
                size: size
            ) ?? NSFont.systemFont(ofSize: size)
            result.addAttribute(.font, value: font, range: range)
        }
        result.removeAttribute(.backgroundColor, range: full)
        return result
    }
}
