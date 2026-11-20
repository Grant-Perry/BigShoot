import AppKit
import Foundation

/// Posts a letter to the pay server, which sends it with Postmark.
/// Until that server has a token, the same letter opens in Mail with the files attached.
@MainActor
enum StudioMailDispatch {
    struct File {
        var url: URL
        var contentType: String
    }

    static func send(
        items: [Any],
        files: [File],
        recipients: [String],
        replyTo: String,
        subject: String,
        plainBody: String,
        html: String,
        payURL: String,
        savedOn: String
    ) async -> QuoteMailResult {
        if let studioKey = PayStudioKey.load() {
            switch await postmark(
                files: files,
                recipients: recipients,
                replyTo: replyTo,
                subject: subject,
                plainBody: plainBody,
                html: html,
                payURL: payURL,
                studioKey: studioKey
            ) {
            case .sent(let messageID):
                return .postmark(messageID: messageID, savedOn: savedOn)
            case .notConfigured:
                break
            case .rejected(let message):
                return .failed(message)
            }
        }

        let outcome = QuoteComposer.email(
            items: items,
            fileURLs: files.map(\.url),
            recipients: recipients,
            subject: subject,
            plainBody: plainBody
        )
        return .handedToMail(mailNote(outcome, recipients: recipients, subject: subject, savedOn: savedOn))
    }

    // MARK: - Private

    private enum PostmarkAttempt {
        case sent(String)
        case notConfigured
        case rejected(String)
    }

    private static func postmark(
        files: [File],
        recipients: [String],
        replyTo: String,
        subject: String,
        plainBody: String,
        html: String,
        payURL: String,
        studioKey: String
    ) async -> PostmarkAttempt {
        var attachments: [[String: String]] = []
        for file in files {
            guard let data = try? Data(contentsOf: file.url) else {
                return .rejected("Couldn’t read \(file.url.lastPathComponent).")
            }
            attachments.append([
                "name": file.url.lastPathComponent,
                "contentType": file.contentType,
                "content": data.base64EncodedString(),
            ])
        }
        let payload: [String: Any] = [
            "to": recipients.first ?? "",
            "replyTo": replyTo,
            "subject": subject,
            "text": plainBody,
            "html": html,
            "payURL": payURL,
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

    private static func mailNote(
        _ outcome: QuoteComposer.EmailOutcome,
        recipients: [String],
        subject: String,
        savedOn: String
    ) -> String {
        let saved = "The letter is saved on this \(savedOn)."
        switch outcome {
        case .composed:
            return "Postmark isn’t live on the server yet, so Apple Mail opened with this letter and the attached files. Send it from there. \(saved)"
        case .attachedInApp(let app):
            let to = recipients.joined(separator: ", ")
            let who = to.isEmpty ? "the client" : to
            return "Postmark isn’t live on the server yet. \(app) opened a new email with the files attached. Add \(who) and the subject “\(subject)”, then paste the message, which is copied. \(saved)"
        case .manualAttach:
            return "Postmark isn’t live on the server yet, and web mail can’t attach files by itself. The files are in Finder: drag them into the new email. The message is copied. \(saved)"
        }
    }
}
