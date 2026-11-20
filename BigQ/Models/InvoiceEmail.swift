import Foundation
import SwiftData

/// A letter kept on an invoice. Reopening it loads this copy into the editor.
@Model
final class InvoiceEmail {
    var invoiceKey: String = ""
    var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    var sentAt: Date?
    var stateRaw: String = QuoteEmailState.draft.rawValue
    var recipient: String = ""
    var subject: String = ""
    var body: String = ""
    var templateName: String = ""
    var payURL: String = ""
    /// Set when Postmark accepts the message. Empty when the letter was handed to Mail.
    var postmarkMessageID: String = ""

    @Relationship(deleteRule: .cascade, inverse: \MailAttachment.invoiceEmail)
    var files: [MailAttachment] = []

    init(
        invoiceKey: String,
        recipient: String = "",
        subject: String = "",
        body: String = "",
        templateName: String = "",
        payURL: String = ""
    ) {
        self.invoiceKey = invoiceKey
        self.recipient = recipient
        self.subject = subject
        self.body = body
        self.templateName = templateName
        self.payURL = payURL
        self.createdAt = .now
        self.updatedAt = .now
    }

    var state: QuoteEmailState {
        get { QuoteEmailState(rawValue: stateRaw) ?? .draft }
        set { stateRaw = newValue.rawValue }
    }

    var statusLine: String {
        let when = sentAt ?? updatedAt
        switch state {
        case .draft:
            return "Draft · \(StudioStamp.string(when))"
        case .sent where !postmarkMessageID.isEmpty:
            return "Sent · \(StudioStamp.string(when))"
        case .sent:
            return "Opened in Mail · \(StudioStamp.string(when))"
        }
    }
}
