import AppKit
import Foundation
import SwiftUI

/// A quote PDF plus the mail text, ready to hand to the system share picker.
struct QuoteShare: Identifiable {
    let id = UUID()
    let quote: Quote
    let pdfURL: URL
    let recipients: [String]
    let subject: String
    let body: String

    /// Body text plus the PDF file. Apple Mail's compose service accepts a file URL (not an item provider).
    var items: [Any] { [body, pdfURL] }
}

enum QuoteComposer {
    enum EmailOutcome {
        /// Apple Mail opened a compose window with the PDF, recipient, subject and message.
        case composed
        /// Another mail app (e.g. Outlook) opened a draft with the PDF attached; the message text is on the clipboard.
        case attachedInApp(String)
        /// Web mail opened a prefilled draft; the PDF was revealed in Finder and copied so it can be dragged or pasted in.
        case manualAttach
    }

    private static let browserFragments = ["chrome", "safari", "firefox", "edgemac", "thebrowser", "brave", "opera", "vivaldi"]

    /// The compose window is hosted by the sharing service; if it is released right after `perform`,
    /// Mail opens addressed but without the body or attachment. Held until the share finishes.
    private static var activeService: NSSharingService?
    private static let serviceKeeper = ServiceKeeper()

    private final class ServiceKeeper: NSObject, NSSharingServiceDelegate {
        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
            QuoteComposer.activeService = nil
        }

        func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            QuoteComposer.activeService = nil
        }
    }

    /// The app that handles `mailto:` links.
    private static var defaultMailApp: URL? {
        guard let probe = URL(string: "mailto:test@example.com") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    /// Emails the quote, picking the route by the default mail app:
    /// - Apple Mail: the system compose window, which carries the attachment, recipient, subject and body.
    /// - Another native app (Outlook): `.composeEmail` drops attachments for third-party apps, so the PDF is
    ///   opened in that app, which starts a draft with it attached, and the message text is copied.
    /// - A browser: a prefilled web-mail draft, with the PDF revealed in Finder to drag in.
    static func email(_ share: QuoteShare) -> EmailOutcome {
        let app = defaultMailApp
        let bundleID = app.flatMap { Bundle(url: $0)?.bundleIdentifier?.lowercased() } ?? ""

        // Only when Apple Mail is the default: the compose service always hands off to the default mail app,
        // and for anything else (Outlook) it drops the attachment and body and cuts the subject at "&".
        if bundleID == "com.apple.mail",
           let service = NSSharingService(named: .composeEmail),
           service.canPerform(withItems: share.items) {
            service.recipients = share.recipients
            service.subject = share.subject
            service.delegate = serviceKeeper
            activeService = service
            service.perform(withItems: share.items)
            return .composed
        }

        let pasteboard = NSPasteboard.general
        if let app, !browserFragments.contains(where: { bundleID.contains($0) }) {
            pasteboard.clearContents()
            pasteboard.setString(share.body, forType: .string)
            NSWorkspace.shared.open([share.pdfURL], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
            return .attachedInApp(name)
        }

        NSWorkspace.shared.activateFileViewerSelecting([share.pdfURL])
        pasteboard.clearContents()
        pasteboard.writeObjects([share.pdfURL as NSURL])

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = share.recipients.joined(separator: ",")
        // Encode "&" and "+" too, so "Grant & Deb" doesn't end the subject early.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value }
        components.percentEncodedQuery = "subject=\(encode(share.subject))&body=\(encode(share.body))"
        if let url = components.url { NSWorkspace.shared.open(url) }
        return .manualAttach
    }

    /// Client-facing email text. With an agreement it walks the client through signing and returning it.
    private static func instructions(
        for quote: Quote,
        clientName: String,
        studioName: String,
        letterhead: String,
        payURL: String
    ) -> String {
        let job = quote.job?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let forJob = job.isEmpty ? "" : " for \(job)"
        let greeting = clientName.isEmpty ? "Hello," : "Hello \(clientName),"

        guard quote.hasAgreement else {
            return """
            \(greeting)

            Thank you for considering \(studioName). Attached is quote \(quote.displayNumber)\(forJob).

            \(payOffer(payURL, due: StudioMoney.string(PayLinkAmount.forQuote(quote)), afterSigning: false))

            \(letterhead)
            """
        }

        return """
        \(greeting)

        Thank you for choosing \(studioName). Attached is quote \(quote.displayNumber)\(forJob), with the agreement included in the same PDF.

        To reserve your date:

        1. Save the attached PDF and open it in Preview (Mac), the Files app (iPhone/iPad), or Adobe Acrobat Reader. Previews inside some mail and messaging apps can't fill in forms.
        2. Review the quote and read the agreement.
        3. On the last page, type your full name in the Client signature box and today's date in the Date box. You can also print, sign by hand, and scan it.
        4. Save the PDF and reply to this email with the signed copy attached.

        \(payOffer(payURL, due: StudioMoney.string(PayLinkAmount.forQuote(quote)), afterSigning: true))

        If you have any questions, just reply to this email.

        \(letterhead)
        """
    }

    private static func payOffer(_ payURL: String, due: String, afterSigning: Bool) -> String {
        guard !payURL.isEmpty else {
            return afterSigning
                ? "Once we receive the signed agreement, we'll send your first invoice for the payment due at signing. Your date is reserved once that payment is received."
                : "Please look it over and reply to this email with any questions, or let us know you'd like to book and we'll send the agreement."
        }
        let lead = afterSigning
            ? "Once you have signed, pay \(due) here. You can pay that amount or a smaller one:"
            : "When you're ready to book, pay \(due) here. You can pay that amount or a smaller one:"
        return """
        \(lead)

        \(payURL)

        Your date is reserved once that payment is received.
        """
    }

    /// Renders the quote PDF to a temp file and builds the mail text.
    /// Goes through the share picker rather than forcing `.composeEmail`, which
    /// opens a browser tab with no attachment when the default mail app is a web client.
    static func prepare(_ quote: Quote) -> QuoteShare? {
        let data = QuotePDFRenderer.render(quote)
        let safeNumber = quote.displayNumber.replacingOccurrences(of: " ", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BigQ-Quote-\(safeNumber).pdf")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            DebugPrint(mode: .error, "Could not write quote PDF: \(error.localizedDescription)")
            return nil
        }

        let name = quote.clientName
        let signedBy = quote.studio?.displayName ?? "Studio"
        let letterhead = quote.studio?.letterhead.joined(separator: "\n") ?? signedBy
        let recipients = [quote.contact?.email].compactMap { email -> String? in
            let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        let body = instructions(
            for: quote,
            clientName: name,
            studioName: signedBy,
            letterhead: letterhead,
            payURL: quote.payToken.isEmpty
                ? ""
                : PayAPI.liveBase.appendingPathComponent("pay").appendingPathComponent(quote.payToken).absoluteString
        )
        return QuoteShare(
            quote: quote,
            pdfURL: url,
            recipients: recipients,
            subject: "Quote \(quote.displayNumber) from \(signedBy)",
            body: body
        )
    }
}

/// Presents the Mac share picker for a quote. `onFinish` reports whether the user picked a service.
struct QuoteSharePicker: NSViewRepresentable {
    var share: QuoteShare?
    var onFinish: (_ share: QuoteShare, _ didShare: Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onFinish = onFinish
        guard let share else {
            context.coordinator.presentedID = nil
            return
        }
        guard context.coordinator.presentedID != share.id, nsView.window != nil else { return }
        context.coordinator.presentedID = share.id
        context.coordinator.share = share
        let picker = NSSharingServicePicker(items: share.items)
        picker.delegate = context.coordinator
        context.coordinator.picker = picker
        picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var picker: NSSharingServicePicker?
        var share: QuoteShare?
        var presentedID: UUID?
        var onFinish: ((QuoteShare, Bool) -> Void)?

        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            sharingServicesForItems items: [Any],
            proposedSharingServices proposedServices: [NSSharingService]
        ) -> [NSSharingService] {
            guard let share else { return proposedServices }
            // Recipients and subject only make sense for the mail service; Messages and others get just the items.
            let mailTitle = NSSharingService(named: .composeEmail)?.menuItemTitle
            for service in proposedServices where service.menuItemTitle == mailTitle {
                service.subject = share.subject
                service.recipients = share.recipients
            }
            return proposedServices
        }

        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            didChoose service: NSSharingService?
        ) {
            let finished = share
            picker = nil
            share = nil
            if let finished { onFinish?(finished, service != nil) }
        }
    }
}
