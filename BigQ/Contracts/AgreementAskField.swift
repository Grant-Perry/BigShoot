import Foundation

/// Fill-in prompts that are not backed by BigQ models — e.g. Bride's Name.
/// Stored in templates as `[Ask: Bride's Name]` and answered when the template is used.
enum AgreementAskField {
    static let marker = "Ask: "
    /// Rich-text HTML often wraps chips in `<span>…</span>`, sometimes mid-token.
    private static let htmlPattern = #"\[Ask:\s*((?:[^\]<]|<[^>]*>)*)\]"#

    static func token(prompt: String) -> String {
        let trimmed = sanitizePrompt(prompt)
        return "[Ask: \(trimmed)]"
    }

    static func isAskToken(_ token: String) -> Bool {
        let inner = token.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return inner.hasPrefix(marker) || inner.lowercased().hasPrefix("ask:")
    }

    /// Unique prompts in document order. HTML tags inside chips are stripped.
    static func prompts(in source: String) -> [String] {
        let haystack = decodeBracketEntities(source)
        guard let regex = try? NSRegularExpression(pattern: htmlPattern) else { return [] }
        let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
        var seen = Set<String>()
        var ordered: [String] = []
        for match in regex.matches(in: haystack, range: range) {
            guard match.numberOfRanges > 1,
                  let promptRange = Range(match.range(at: 1), in: haystack) else { continue }
            let prompt = sanitizePrompt(String(haystack[promptRange]))
            guard !prompt.isEmpty, seen.insert(prompt).inserted else { continue }
            ordered.append(prompt)
        }
        return ordered
    }

    static func hasUnresolvedAsks(in source: String) -> Bool {
        !prompts(in: source).isEmpty
    }

    /// Replaces each `[Ask: Prompt]` (plain or HTML-wrapped) with the matching answer.
    /// Blank answers leave the token.
    static func apply(_ source: String, answers: [String: String]) -> String {
        // Normalize entity-encoded brackets first so Cocoa HTML Writer output still matches.
        var result = decodeBracketEntities(source)
        guard let regex = try? NSRegularExpression(pattern: htmlPattern) else { return result }
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let promptRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let prompt = sanitizePrompt(String(result[promptRange]))
            let answer = answers[prompt]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !answer.isEmpty else { continue }
            result.replaceSubrange(fullRange, with: escapeHTML(answer))
        }
        return result
    }

    /// Cocoa HTML Writer sometimes emits `&#x5b;` / `&#x5d;` for `[` / `]`.
    private static func decodeBracketEntities(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&#x5b;", with: "[", options: .caseInsensitive)
            .replacingOccurrences(of: "&#x5d;", with: "]", options: .caseInsensitive)
            .replacingOccurrences(of: "&#91;", with: "[")
            .replacingOccurrences(of: "&#93;", with: "]")
            .replacingOccurrences(of: "&lsqb;", with: "[", options: .caseInsensitive)
            .replacingOccurrences(of: "&rsqb;", with: "]", options: .caseInsensitive)
    }

    /// Pulls a human prompt out of whatever the HTML exporter stuffed between the brackets.
    static func sanitizePrompt(_ raw: String) -> String {
        var text = AgreementInlineStyle.stripped(raw)
        let breaks = ["</p>", "</div>", "</li>", "<br>", "<br/>", "<br />"]
        for tag in breaks {
            text = text.replacingOccurrences(of: tag, with: " ", options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        return text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
