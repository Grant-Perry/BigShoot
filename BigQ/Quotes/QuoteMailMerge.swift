import Foundation
import SwiftData

enum QuoteMailKey {
    static func existing(for quote: Quote) -> String {
        quote.archiveID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stable id shared with backups. Assigned the first time a letter is saved.
    static func ensure(for quote: Quote) -> String {
        let trimmed = existing(for: quote)
        if !trimmed.isEmpty { return trimmed }
        let assigned = UUID().uuidString
        quote.archiveID = assigned
        return assigned
    }
}

enum QuoteMailBuiltin: String, CaseIterable, Identifiable {
    case proposal
    case proposalAndAgreement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .proposal: "Proposal"
        case .proposalAndAgreement: "Proposal and agreement"
        }
    }
}

enum QuoteMailPick: Hashable {
    case current
    case builtin(QuoteMailBuiltin)
    case saved(PersistentIdentifier)
}

enum QuoteMailMerge {
    /// Visible label for `[Pay Link]`. The address stays in the link, not in the letter.
    static let payLinkPhrase = "You can pay your retainer here"

    static let tokenHint = "These fill from this quote, same as an agreement: [Client Name]  [Studio Name]  [Quote Number]  [Job Name]  [Event Date]  [Retainer]  [Pay Link]  [Letterhead]"

    /// Fields this letter starts with. Any agreement variable can be inserted too.
    static let letterVariables: [AgreementVariable] = [
        AgreementVariable("Client Name"),
        AgreementVariable("Studio Name"),
        AgreementVariable("Quote Number"),
        AgreementVariable("Job Name"),
        AgreementVariable("Event Date"),
        AgreementVariable("Retainer"),
        AgreementVariable(label: "Pay Link", token: "[Pay Link]"),
        AgreementVariable(label: "Letterhead", token: "[Letterhead]"),
    ]

    static let subjectTemplate = "Quote [Quote Number] from [Studio Name]"

    static func subject(for quote: Quote) -> String {
        fill(subjectTemplate, quote: quote)
    }

    static func recipients(for quote: Quote) -> [String] {
        let trimmed = quote.contact?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? [] : [trimmed]
    }

    static func payURL(for quote: Quote) -> String {
        guard !quote.payToken.isEmpty else { return "" }
        return PayAPI.liveBase
            .appendingPathComponent("pay")
            .appendingPathComponent(quote.payToken)
            .absoluteString
    }

    /// HTML the client can click. The retainer phrase is the link; the address is the href.
    static func htmlLetter(_ body: String, quote: Quote) -> String {
        let url = payURL(for: quote)
        let blocks = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let paragraphs = blocks.map { block -> String in
            var html = escapeHTML(block).replacingOccurrences(of: "\n", with: "<br>")
            if !url.isEmpty {
                let href = escapeHTML(url)
                html = html.replacingOccurrences(
                    of: payLinkPhrase,
                    with: "<a href=\"\(href)\">\(payLinkPhrase)</a>"
                )
            }
            return "<p style=\"margin: 0 0 16px; line-height: 1.65;\">\(html)</p>"
        }
        let inner = paragraphs.isEmpty ? "<p></p>" : paragraphs.joined(separator: "\n")
        return """
        <!DOCTYPE html><html><body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 16px; line-height: 1.65; color: #1c1c1e;">\(inner)</body></html>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Plain-text copy. The address follows the retainer phrase so a text-only client can still open it.
    static func plainText(_ body: String, quote: Quote) -> String {
        let url = payURL(for: quote)
        guard !url.isEmpty, body.contains(payLinkPhrase), !body.contains(url) else { return body }
        return body.replacingOccurrences(of: payLinkPhrase, with: "\(payLinkPhrase)\n\(url)")
    }

    static func letter(for quote: Quote, signingSteps: Bool) -> String {
        fill(bodyTemplate(signingSteps: signingSteps), quote: quote)
    }

    static func apply(template: EmailTemplate, to quote: Quote) -> (subject: String, body: String) {
        (
            fill(template.subject, quote: quote),
            fill(template.body, quote: quote)
        )
    }

    /// Turns this quote’s names, amounts, and pay link back into variables for the next quote.
    static func templatize(_ text: String, quote: Quote) -> String {
        let context = mergeContext(for: quote)
        let letterhead = Self.letterhead(for: quote.studio)
        let amount = StudioMoney.string(PayLinkAmount.forQuote(quote).amount)
        var pairs: [(String, String)] = [
            (letterhead, "[Letterhead]"),
            (payURL(for: quote), "[Pay Link]"),
            (payLinkPhrase, "[Pay Link]"),
            (amount, "[Retainer]"),
            (context.totalAmount, "[Total Amount]"),
            (context.remainingBalance, "[Remaining Balance]"),
            (context.subtotal, "[Subtotal]"),
            (context.totalTax, "[Total Tax]"),
            (context.totalDiscount, "[Total Discount]"),
            (context.clientAddress, "[Client Full Address]"),
            (context.clientName, "[Client Name]"),
            (context.clientEmail, "[Client Email]"),
            (context.clientPhone, "[Client Phone]"),
            (context.studioName, "[Studio Name]"),
            (context.studioEmail, "[Studio Email]"),
            (context.studioPhone, "[Studio Phone]"),
            (context.studioAddress, "[Studio Address]"),
            (context.jobName, "[Job Name]"),
            (context.coupleFirstNames, "[First+First Couple]"),
            (context.brideLastName, "[Bride Last Name]"),
            (context.groomLastName, "[Groom Last Name]"),
            (context.brideFirstName, "[Bride First Name]"),
            (context.groomFirstName, "[Groom First Name]"),
            (context.eventDate, "[Event Date]"),
            (context.quoteNumber, "[Quote Number]"),
        ]
        pairs.sort { $0.0.count > $1.0.count }
        var result = text
        for (value, token) in pairs where value.count >= 3 && value != "—" {
            result = result.replacingOccurrences(of: value, with: token)
        }
        let number = context.quoteNumber
        if !number.isEmpty {
            result = result.replacingOccurrences(of: "quote \(number)", with: "quote [Quote Number]")
            result = result.replacingOccurrences(of: "Quote \(number)", with: "Quote [Quote Number]")
        }
        return result
    }

    /// Fills agreement variables, plus `[Pay Link]` and `[Letterhead]`. `[Retainer]` is the amount due now.
    static func fill(_ text: String, quote: Quote) -> String {
        let context = mergeContext(for: quote)
        let job = quote.job?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var result = text
        if context.clientName.isEmpty {
            result = result.replacingOccurrences(of: "Hello [Client Name],", with: "Hello,")
        }
        if job.isEmpty {
            result = result.replacingOccurrences(of: " for [Job Name]", with: "")
        }
        if quote.total <= 0, payURL(for: quote).isEmpty {
            result = result.replacingOccurrences(of: bookingPay, with: bookingFallback)
            result = result.replacingOccurrences(of: signingPay, with: signingFallback)
        }
        result = AgreementMerge.resolve(result, with: context)
        result = plainFromMerge(result)
        let amount = StudioMoney.string(PayLinkAmount.forQuote(quote).amount)
        let letterhead = Self.letterhead(for: quote.studio)
        let extras = [
            "[Letterhead]": letterhead,
            "[Amount]": amount,
            "[Pay Link]": payLinkText(for: quote),
            "[Client]": context.clientName,
            "[Studio]": context.studioName,
            "[Quote]": context.quoteNumber,
            "[Job]": context.jobName,
            "[Event]": context.eventDate == "—" ? "" : context.eventDate,
        ]
        return extras.reduce(result) { partial, pair in
            partial.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    /// Appends the retainer link when a letter was written before the link existed.
    static func ensuringPayLink(_ body: String, quote: Quote) -> String {
        let filled = fill(body, quote: quote)
        let url = payURL(for: quote)
        if url.isEmpty || filled.contains(payLinkPhrase) || filled.contains(url) {
            return filled
        }
        let due = StudioMoney.string(PayLinkAmount.forQuote(quote).amount)
        let lead = quote.hasAgreement
            ? "Once you have signed, pay \(due) here. You can pay that amount or a smaller one."
            : "When you're ready to book, pay \(due) here. You can pay that amount or a smaller one."
        let offer = """
        \(lead)

        \(payLinkPhrase)

        Your date is reserved once that payment is received.
        """
        let trimmed = filled.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return offer }
        return trimmed + "\n\n" + offer
    }

    // MARK: - Private

    private static let bookingPay = """
    When you're ready to book, pay [Retainer] here. You can pay that amount or a smaller one.

    [Pay Link]

    Your date is reserved once that payment is received.
    """

    private static let signingPay = """
    Once you have signed, pay [Retainer] here. You can pay that amount or a smaller one.

    [Pay Link]

    Your date is reserved once that payment is received.
    """

    private static let bookingFallback = "Please look it over and reply to this email with any questions, or let us know you'd like to book and we'll send the agreement."

    private static let signingFallback = "Once we receive the signed agreement, we'll send your first invoice for the payment due at signing. Your date is reserved once that payment is received."

    private static func bodyTemplate(signingSteps: Bool) -> String {
        if !signingSteps {
            return """
            Hello [Client Name],

            Thank you for considering [Studio Name]. Attached is quote [Quote Number] for [Job Name].

            \(bookingPay)

            [Letterhead]
            """
        }
        return """
        Hello [Client Name],

        Thank you for choosing [Studio Name]. Attached is quote [Quote Number] for [Job Name], and the agreement is attached as its own PDF.

        To reserve your date:

        1. Save the attached PDFs and open them in Preview (Mac), the Files app (iPhone/iPad), or Adobe Acrobat Reader. Previews inside some mail and messaging apps can't fill in forms.
        2. Review the quote and read the agreement.
        3. On the last page of the agreement, type your full name in the Client signature box and today's date in the Date box. You can also print, sign by hand, and scan it.
        4. Save the PDF and reply to this email with the signed copy attached.

        \(signingPay)

        If you have any questions, just reply to this email.

        [Letterhead]
        """
    }

    private static func mergeContext(for quote: Quote) -> AgreementMergeContext {
        var context = AgreementMerge.context(
            contact: quote.contact,
            job: quote.job,
            studio: quote.studio,
            quote: quote
        )
        if context.clientName == "No client" || context.clientName == "Unnamed contact" {
            context.clientName = ""
        }
        let job = quote.job?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if job.isEmpty { context.jobName = "" }
        return context
    }

    /// Studio name, email, phone, and address. Skips the “Unnamed studio” screen label.
    private static func letterhead(for studio: StudioBrand?) -> String {
        guard let studio else { return "" }
        let name = studio.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([name] + studio.detailLines).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func payLinkText(for quote: Quote) -> String {
        if quote.total <= 0, payURL(for: quote).isEmpty { return "" }
        return payLinkPhrase
    }

    /// Agreement fields such as `[Terms]` arrive as HTML. The letter is plain text until send.
    private static func plainFromMerge(_ text: String) -> String {
        guard text.contains("<") || text.contains("&") else { return text }
        var result = text
        let breaks = ["<br>", "<br/>", "<br />", "&#8232;", "&#x2028;"]
        for token in breaks {
            result = result.replacingOccurrences(of: token, with: "\n", options: .caseInsensitive)
        }
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&",
            "&nbsp;": " ",
            "&quot;": "\"",
            "&#39;": "'",
        ]
        for (entity, value) in entities {
            result = result.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        return result
    }
}
