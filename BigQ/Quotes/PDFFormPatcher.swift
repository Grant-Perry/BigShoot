import Foundation

/// PDFKit writes widget annotations without an `/AcroForm` entry and with a malformed `/DA`
/// (a name instead of a string), so viewers refuse typing. This appends an incremental update
/// that registers the text fields in an AcroForm and rewrites each field with a valid `/DA`.
enum PDFFormPatcher {
    private static let defaultAppearance = "(/Helv 12 Tf 0 g)"
    private static let formFonts = "<< /Font << /Helv << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> >> >>"

    static func patch(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .isoLatin1) else { return data }
        let ns = text as NSString
        guard let objectRegex = try? NSRegularExpression(
            pattern: #"(\d+) 0 obj\s*(<<(?:(?!endobj).)*?>>)\s*endobj"#,
            options: [.dotMatchesLineSeparators]
        ) else { return data }

        var fields: [(number: Int, dict: String)] = []
        var catalog: (number: Int, dict: String)?
        for match in objectRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let number = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let dict = ns.substring(with: match.range(at: 2))
            if dict.contains("/FT /Tx") {
                fields.append((number, dict))
            } else if dict.contains("/Type /Catalog") {
                catalog = (number, dict)
            }
        }
        guard !fields.isEmpty, let catalog, !catalog.dict.contains("/AcroForm") else { return data }

        guard let startRange = text.range(of: "startxref", options: .backwards),
              let previous = Int(text[startRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(while: \.isNumber)),
              let sizeMatch = text.range(of: #"/Size (\d+)"#, options: [.regularExpression, .backwards]),
              let size = Int(text[sizeMatch].dropFirst(6)),
              let rootMatch = text.range(of: #"/Root (\d+) 0 R"#, options: [.regularExpression, .backwards])
        else { return data }
        let rootRef = String(text[rootMatch])

        var update = data
        if update.last != 0x0A { update.append(0x0A) }
        var offsets: [(number: Int, offset: Int)] = []

        func append(object number: Int, body: String) {
            offsets.append((number, update.count))
            update.append(Data("\(number) 0 obj\n\(body)\nendobj\n".utf8))
        }

        for field in fields {
            var dict = field.dict
            if let range = dict.range(of: #"/DA /\S+"#, options: .regularExpression) {
                dict.replaceSubrange(range, with: "/DA \(defaultAppearance)")
            } else if let close = dict.range(of: ">>", options: .backwards) {
                dict.replaceSubrange(close, with: "/DA \(defaultAppearance) >>")
            }
            append(object: field.number, body: dict)
        }

        let refs = fields.map { "\($0.number) 0 R" }.joined(separator: " ")
        var catalogDict = catalog.dict
        if let close = catalogDict.range(of: ">>", options: .backwards) {
            catalogDict.replaceSubrange(
                close,
                with: "/AcroForm << /Fields [ \(refs) ] /DA \(defaultAppearance) /DR \(formFonts) >> >>"
            )
        }
        append(object: catalog.number, body: catalogDict)

        let xrefStart = update.count
        var xref = "xref\n"
        for entry in offsets.sorted(by: { $0.number < $1.number }) {
            xref += "\(entry.number) 1\n" + String(format: "%010d 00000 n \n", entry.offset)
        }
        xref += "trailer\n<< /Size \(size) \(rootRef) /Prev \(previous) >>\nstartxref\n\(xrefStart)\n%%EOF\n"
        update.append(Data(xref.utf8))
        return update
    }
}
