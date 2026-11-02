import AppKit
import Foundation

enum QuoteComposer {
    enum Outcome {
        case composed
        case unavailable
    }

    static func compose(_ quote: Quote) -> Outcome {
        let data = QuotePDFRenderer.render(quote)
        let safeNumber = quote.displayNumber.replacingOccurrences(of: " ", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BigQ-Quote-\(safeNumber).pdf")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            DebugPrint(mode: .error, "Could not write quote PDF: \(error.localizedDescription)")
            return .unavailable
        }

        guard let service = NSSharingService(named: .composeEmail),
              service.canPerform(withItems: [url]) else {
            return .unavailable
        }

        let name = quote.clientName
        let signedBy = quote.studio?.displayName ?? "Studio"
        let letterhead = quote.studio?.letterhead.joined(separator: "\n") ?? signedBy
        service.recipients = [quote.contact?.email].compactMap { email in
            let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        service.subject = "Quote \(quote.displayNumber) from \(signedBy)"
        let agreementNote = quote.hasAgreement
            ? "Please review the attached quote and agreement, sign the agreement, and return a copy."
            : "Please review the attached quote."
        let body = """
        Hello \(name),

        \(agreementNote)

        \(letterhead)
        """
        service.perform(withItems: [body, url])
        return .composed
    }
}
