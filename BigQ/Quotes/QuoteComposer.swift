import AppKit
import Foundation
import SwiftUI

/// A quote PDF plus the mail text, ready to hand to the system share picker.
struct QuoteShare: Identifiable {
    let id = UUID()
    let quote: Quote
    let pdfURL: URL
    let agreementURL: URL?
    let recipients: [String]
    let subject: String
    let body: String

    /// Body text plus the PDF files. Apple Mail's compose service accepts a file URL (not an item provider).
    /// The retainer phrase carries the pay address as a link. Postmark HTML does the same.
    var items: [Any] {
        var values: [Any] = [linkedLetter, pdfURL]
        if let agreementURL { values.append(agreementURL) }
        return values
    }

    var fileURLs: [URL] {
        [pdfURL, agreementURL].compactMap { $0 }
    }

    /// Retainer phrase as a real link. The address stays on the next line for plain-text mail.
    private var linkedLetter: NSAttributedString {
        let plain = QuoteMailMerge.plainText(body, quote: quote)
        let letter = NSMutableAttributedString(string: plain)
        let address = QuoteMailMerge.payURL(for: quote)
        guard let url = URL(string: address), !address.isEmpty,
              let range = plain.range(of: QuoteMailMerge.payLinkPhrase) else { return letter }
        let nsRange = NSRange(range, in: plain)
        letter.addAttribute(.link, value: url, range: nsRange)
        letter.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        return letter
    }
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
            pasteboard.setString(QuoteMailMerge.plainText(share.body, quote: share.quote), forType: .string)
            NSWorkspace.shared.open(share.fileURLs, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
            return .attachedInApp(name)
        }

        NSWorkspace.shared.activateFileViewerSelecting(share.fileURLs)
        pasteboard.clearContents()
        pasteboard.writeObjects(share.fileURLs.map { $0 as NSURL })

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = share.recipients.joined(separator: ",")
        // Encode "&" and "+" too, so "Grant & Deb" doesn't end the subject early.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value }
        let mailBody = QuoteMailMerge.plainText(share.body, quote: share.quote)
        components.percentEncodedQuery = "subject=\(encode(share.subject))&body=\(encode(mailBody))"
        if let url = components.url { NSWorkspace.shared.open(url) }
        return .manualAttach
    }

    /// Renders the quote PDF, and the agreement PDF when requested, then returns the letter to hand off.
    static func write(
        quote: Quote,
        recipients: [String],
        subject: String,
        body: String,
        attachAgreement: Bool
    ) -> QuoteShare? {
        let safeNumber = Self.fileToken(quote.displayNumber)
        let directory = FileManager.default.temporaryDirectory
        let quoteURL = directory.appendingPathComponent(Self.attachmentName(quote: quote, role: "Quote"))
        do {
            try QuotePDFRenderer.render(quote, includeAgreement: false).write(to: quoteURL, options: .atomic)
        } catch {
            DebugPrint(mode: .error, "Could not write quote PDF: \(error.localizedDescription)")
            return nil
        }

        var agreementURL: URL?
        if attachAgreement, quote.hasAgreement {
            let url = directory.appendingPathComponent(Self.attachmentName(quote: quote, role: "Agreement"))
            do {
                try QuotePDFRenderer.renderAgreementOnly(quote).write(to: url, options: .atomic)
                agreementURL = url
            } catch {
                DebugPrint(mode: .error, "Could not write agreement PDF: \(error.localizedDescription)")
                return nil
            }
        }

        return QuoteShare(
            quote: quote,
            pdfURL: quoteURL,
            agreementURL: agreementURL,
            recipients: recipients,
            subject: subject,
            body: body
        )
    }

    /// Postmark accepts a plain PDF name. Strip anything else out of the quote number.
    private static func fileToken(_ number: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let mapped = number.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let token = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return token.isEmpty ? "Draft" : token
    }

    /// What the client sees on the file. The studio name, not the app name.
    private static func attachmentName(quote: Quote, role: String) -> String {
        let stored = quote.studio?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let studio = stored.isEmpty ? StudioBrand.defaultName : stored
        let number = fileToken(quote.displayNumber)
        return "\(studio) - \(role) \(number).pdf"
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
