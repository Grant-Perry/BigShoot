import AppKit
import Foundation

enum ReminderComposer {
    enum Outcome {
        case composed
        case unavailable
    }

    static func compose(invoice: Invoice) -> Outcome {
        let data = InvoicePDFRenderer.render(invoice)
        let safeNumber = invoice.displayNumber.replacingOccurrences(of: " ", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GrantDeb-\(safeNumber).pdf")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            DebugPrint(mode: .error, "Could not write reminder PDF: \(error.localizedDescription)")
            return .unavailable
        }

        guard let service = NSSharingService(named: .composeEmail),
              service.canPerform(withItems: [url]) else {
            return .unavailable
        }

        let name = invoice.clientName
        let balance = StudioMoney.string(invoice.balance)
        let due = StudioDay.string(invoice.dueDate)
        let signedBy = invoice.studio?.displayName ?? "Studio"
        let letterhead = invoice.studio?.letterhead.joined(separator: "\n") ?? signedBy
        service.recipients = [invoice.contact?.email].compactMap { email in
            let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        service.subject = "Invoice \(invoice.displayNumber) from \(signedBy)"
        let body = """
        Hello \(name),

        A reminder that invoice \(invoice.displayNumber) has a balance of \(balance), due \(due).

        \(letterhead)
        """
        service.perform(withItems: [body, url])
        return .composed
    }
}
