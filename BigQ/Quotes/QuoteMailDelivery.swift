import Foundation

enum QuoteMailResult {
    case postmark(messageID: String)
    case handedToMail(String)
    case failed(String)

    var note: String {
        switch self {
        case .postmark:
            "Sent through Postmark. The letter is saved on this quote."
        case .handedToMail(let message):
            message
        case .failed(let message):
            message
        }
    }

    var messageID: String {
        if case .postmark(let id) = self { return id }
        return ""
    }

    var didLeaveTheMac: Bool {
        if case .failed = self { return false }
        return true
    }
}

/// Posts the letter to the pay server, which sends it with Postmark.
/// Until that server has a token, the same letter opens in Mail with the PDFs attached.
@MainActor
enum QuoteMailDelivery {
    static func send(
        quote: Quote,
        recipient: String,
        replyTo: String,
        subject: String,
        body: String,
        attachAgreement: Bool
    ) async -> QuoteMailResult {
        guard let share = QuoteComposer.write(
            quote: quote,
            recipients: [recipient],
            subject: subject,
            body: body,
            attachAgreement: attachAgreement
        ) else {
            return .failed("Couldn’t create the quote PDF.")
        }

        if let studioKey = PayStudioKey.load() {
            switch await postmark(share: share, replyTo: replyTo, studioKey: studioKey) {
            case .sent(let messageID):
                return .postmark(messageID: messageID)
            case .notConfigured:
                break
            case .rejected(let message):
                return .failed(message)
            }
        }

        let outcome = QuoteComposer.email(share)
        return .handedToMail(mailNote(outcome, share: share))
    }

    // MARK: - Private

    private enum PostmarkAttempt {
        case sent(String)
        case notConfigured
        case rejected(String)
    }

    private static func postmark(share: QuoteShare, replyTo: String, studioKey: String) async -> PostmarkAttempt {
        var attachments: [[String: String]] = []
        for url in share.fileURLs {
            guard let data = try? Data(contentsOf: url) else {
                return .rejected("Couldn’t read \(url.lastPathComponent).")
            }
            attachments.append([
                "name": url.lastPathComponent,
                "contentType": "application/pdf",
                "content": data.base64EncodedString(),
            ])
        }
        let payload: [String: Any] = [
            "to": share.recipients.first ?? "",
            "replyTo": replyTo,
            "subject": share.subject,
            "text": share.body,
            "html": QuoteMailMerge.htmlLetter(share.body, quote: share.quote),
            "payURL": QuoteMailMerge.payURL(for: share.quote),
            "attachments": attachments,
        ]
        var request = URLRequest(url: endpoint("/api/quote-mail"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(studioKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .notConfigured
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = json?["code"] as? String ?? ""
        if status == 404 || code == "postmark_not_configured" {
            return .notConfigured
        }
        if !(200...299).contains(status) {
            let message = (json?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .rejected(message.isEmpty ? "Postmark rejected the letter." : message)
        }
        let messageID = (json?["messageID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if messageID.isEmpty {
            return .rejected("Postmark accepted the letter but didn’t return an id.")
        }
        return .sent(messageID)
    }

    private static func endpoint(_ path: String) -> URL {
        var components = URLComponents(url: PayAPI.liveBase, resolvingAgainstBaseURL: false)
        components?.path = path
        return components?.url ?? PayAPI.liveBase
    }

    private static func mailNote(_ outcome: QuoteComposer.EmailOutcome, share: QuoteShare) -> String {
        let saved = "The letter is saved on this quote."
        switch outcome {
        case .composed:
            return "Postmark isn’t live on the server yet, so Apple Mail opened with this letter and the PDFs. Send it from there. \(saved)"
        case .attachedInApp(let app):
            let to = share.recipients.joined(separator: ", ")
            let who = to.isEmpty ? "the client" : to
            return "Postmark isn’t live on the server yet. \(app) opened a new email with the PDFs attached. Add \(who) and the subject “\(share.subject)”, then paste the message, which is copied. \(saved)"
        case .manualAttach:
            return "Postmark isn’t live on the server yet, and web mail can’t attach files by itself. The PDFs are in Finder: drag them into the new email. The message is copied. \(saved)"
        }
    }
}
