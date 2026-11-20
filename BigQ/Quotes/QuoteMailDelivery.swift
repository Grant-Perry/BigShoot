import Foundation

enum QuoteMailResult {
    case postmark(messageID: String, savedOn: String)
    case handedToMail(String)
    case failed(String)

    var note: String {
        switch self {
        case .postmark(_, let savedOn):
            "Sent through Postmark. The letter is saved on this \(savedOn)."
        case .handedToMail(let message):
            message
        case .failed(let message):
            message
        }
    }

    var messageID: String {
        if case .postmark(let id, _) = self { return id }
        return ""
    }

    var didLeaveTheMac: Bool {
        if case .failed = self { return false }
        return true
    }
}

/// Posts the quote letter. Postmark when the pay server can send, otherwise Mail on this Mac.
@MainActor
enum QuoteMailDelivery {
    static func send(
        quote: Quote,
        recipient: String,
        replyTo: String,
        subject: String,
        body: String,
        attachAgreement: Bool,
        extras: [MailFileDraft] = []
    ) async -> QuoteMailResult {
        guard let share = QuoteComposer.write(
            quote: quote,
            recipients: [recipient],
            subject: subject,
            body: body,
            attachAgreement: attachAgreement,
            extras: extras
        ) else {
            return .failed("Couldn’t create the quote PDF.")
        }
        return await StudioMailDispatch.send(
            items: share.items,
            files: share.outboundFiles,
            recipients: share.recipients,
            replyTo: replyTo,
            subject: share.subject,
            plainBody: QuoteMailMerge.plainText(share.body, quote: share.quote),
            html: QuoteMailMerge.htmlLetter(share.body, quote: share.quote),
            payURL: QuoteMailMerge.payURL(for: share.quote),
            savedOn: "quote"
        )
    }
}
