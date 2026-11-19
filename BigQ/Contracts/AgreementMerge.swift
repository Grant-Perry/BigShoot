import Foundation

/// Context used to replace `[Field]` tokens when a template becomes a real agreement.
struct AgreementMergeContext: Sendable {
    var clientName: String = ""
    var clientFirstName: String = ""
    var clientLastName: String = ""
    var clientEmail: String = ""
    var clientPhone: String = ""
    var clientCompany: String = ""
    var clientAddress: String = ""
    var jobName: String = ""
    var jobType: String = ""
    var jobStatus: String = ""
    var eventDate: String = ""
    var primaryContactName: String = ""
    var brideFirstName: String = ""
    var brideLastName: String = ""
    var groomFirstName: String = ""
    var groomLastName: String = ""
    /// Both first names, as in `Cindy + Brent`.
    var coupleFirstNames: String = ""
    var studioName: String = ""
    var studioEmail: String = ""
    var studioPhone: String = ""
    var studioAddress: String = ""
    var quoteNumber: String = ""
    var quoteDate: String = ""
    var validUntil: String = ""
    /// Line items only — before tax, shipping, and discount.
    var subtotal: String = ""
    /// Grand total: subtotal + tax + shipping − discount.
    var totalAmount: String = ""
    var totalTax: String = ""
    var totalDiscount: String = ""
    var remainingBalance: String = ""
    /// First payment due, or the whole balance when nothing is scheduled ahead of it.
    var retainer: String = ""
    /// Multi-line payment schedule HTML (`<br>` separated) for `[Terms]`.
    var terms: String = ""
    /// Full quote packages / line items for `[Quote Details]`.
    var quoteDetails: String = ""
    var dateSigned: String = ""
    var agreementCreatedDate: String = ""
}

enum AgreementMerge {
    static func context(
        contact: Contact?,
        job: Job?,
        studio: StudioBrand?,
        quote: Quote? = nil,
        now: Date = .now
    ) -> AgreementMergeContext {
        var ctx = AgreementMergeContext()
        let client = job?.contact ?? contact
        if let client {
            ctx.clientName = storedPersonName(client)
            ctx.clientFirstName = client.givenName
            ctx.clientLastName = client.familyName
            ctx.clientEmail = client.email.trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.clientPhone = client.phone.trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.clientCompany = client.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.clientAddress = client.address.trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.primaryContactName = ctx.clientName
        }
        if let job {
            ctx.jobName = job.name.trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.jobType = job.jobType.trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.jobStatus = job.status
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.eventDate = day(job.eventDate)
            if let bride = job.bride {
                ctx.brideFirstName = bride.givenName
                ctx.brideLastName = bride.familyName
            }
            if let groom = job.groom {
                ctx.groomFirstName = groom.givenName
                ctx.groomLastName = groom.familyName
            }
            if !ctx.brideFirstName.isEmpty, !ctx.groomFirstName.isEmpty {
                ctx.coupleFirstNames = "\(ctx.brideFirstName) + \(ctx.groomFirstName)"
            }
        }
        if let studio {
            ctx.studioName = studio.name.trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.studioEmail = studio.email.trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.studioPhone = studio.phone.trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.studioAddress = studio.address.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let quote {
            ctx.quoteNumber = quote.number.trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.quoteDate = day(quote.quoteDate)
            ctx.validUntil = day(quote.validUntil)
            let subtotal = quote.lines.reduce(Decimal.zero) { $0 + $1.lineTotal }
            ctx.subtotal = StudioMoney.string(subtotal)
            ctx.totalAmount = StudioMoney.string(quote.total)
            ctx.totalTax = StudioMoney.string(quote.tax)
            ctx.totalDiscount = StudioMoney.string(quote.discount)
            ctx.remainingBalance = StudioMoney.string(quote.total)
            ctx.retainer = StudioMoney.string(PayLinkAmount.forQuote(quote).amount)
            ctx.terms = QuotePaymentSchedule.agreementTermsHTML(for: quote)
            ctx.quoteDetails = QuoteMath.agreementDetailsHTML(for: quote)
            ctx.dateSigned = day(quote.signedAt)
            if ctx.clientName.isEmpty {
                ctx.clientName = quote.billToName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if ctx.clientAddress.isEmpty {
                ctx.clientAddress = (job?.contact ?? quote.contact)?.address
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
        }
        // Job contracts (and quotes with no schedule yet) pull `[Terms]` from the job.
        if ctx.terms.isEmpty, let job {
            ctx.terms = QuotePaymentSchedule.agreementTermsHTML(for: job)
        }
        if ctx.retainer.isEmpty, let job, let first = job.sortedPaymentTerms.first(where: { $0.amount > 0 }) {
            ctx.retainer = StudioMoney.string(first.amount)
        }
        ctx.agreementCreatedDate = day(now)
        return ctx
    }

    /// A stored date, or nothing. Screen labels use an em dash for “no date”; a contract must not.
    static func day(_ date: Date?) -> String {
        guard let date else { return "" }
        return StudioDay.string(date)
    }

    /// The name on the contact record. Not “Unnamed contact” and not “No client”.
    private static func storedPersonName(_ contact: Contact) -> String {
        let full = contact.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        let combined = "\(contact.givenName) \(contact.familyName)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !combined.isEmpty { return combined }
        return contact.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces every known `[Field]` token. Unknown tokens are left alone.
    static func resolve(_ source: String, with context: AgreementMergeContext) -> String {
        resolve(source, with: context, skipEmptyValues: false)
    }

    /// - Parameter skipEmptyValues: When true, tokens with no data stay put (editor live-fill).
    ///   Final PDF / save passes false so blanks clear out of the finished agreement.
    static func resolve(
        _ source: String,
        with context: AgreementMergeContext,
        skipEmptyValues: Bool
    ) -> String {
        var result = source
        for (token, value) in values(from: context) {
            if skipEmptyValues, value.isEmpty { continue }
            result = result.replacingOccurrences(of: token, with: value)
        }
        // ShootQ aliases that map onto the same BigQ fields.
        let aliases: [(String, String)] = [
            ("[Primary Client Name]", context.clientName),
            ("[Full Name]", context.clientName),
            ("[First Name]", context.clientFirstName),
            ("[Last Name]", context.clientLastName),
            ("[Email]", context.clientEmail),
            ("[Phone]", context.clientPhone),
            ("[Company Name]", context.clientCompany),
            ("[Full Address]", context.clientAddress),
            ("[Primary Event Date]", context.eventDate),
            ("[Job Start Date]", context.eventDate),
            ("[Main Event Start Date]", context.eventDate),
            ("[Event Type]", context.jobType),
            ("[Current Date]", context.agreementCreatedDate),
            ("[Studio Phone Number]", context.studioPhone),
            ("[Company Email]", context.studioEmail),
            ("[Company Phone]", context.studioPhone),
            ("[Company Address]", context.studioAddress),
        ]
        for (token, value) in aliases {
            if skipEmptyValues, value.isEmpty { continue }
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }

    private static func values(from context: AgreementMergeContext) -> [(String, String)] {
        [
            ("[Client Name]", context.clientName),
            ("[Client First Name]", context.clientFirstName),
            ("[Client Last Name]", context.clientLastName),
            ("[Client Email]", context.clientEmail),
            ("[Client Phone]", context.clientPhone),
            ("[Client Company]", context.clientCompany),
            ("[Client Full Address]", context.clientAddress),
            ("[Job Name]", context.jobName),
            ("[Job Type]", context.jobType),
            ("[Job Status]", context.jobStatus),
            ("[Event Date]", context.eventDate),
            ("[Primary Contact Name]", context.primaryContactName),
            ("[Bride First Name]", context.brideFirstName),
            ("[Bride Last Name]", context.brideLastName),
            ("[Groom First Name]", context.groomFirstName),
            ("[Groom Last Name]", context.groomLastName),
            ("[First+First Couple]", context.coupleFirstNames),
            ("[Studio Name]", context.studioName),
            ("[Studio Email]", context.studioEmail),
            ("[Studio Phone]", context.studioPhone),
            ("[Studio Address]", context.studioAddress),
            ("[Quote Number]", context.quoteNumber),
            ("[Quote Date]", context.quoteDate),
            ("[Valid Until]", context.validUntil),
            ("[Subtotal]", context.subtotal),
            ("[Total before tax]", context.subtotal),
            ("[Total Amount]", context.totalAmount),
            ("[Total Tax]", context.totalTax),
            ("[Total Discount]", context.totalDiscount),
            ("[Remaining Balance]", context.remainingBalance),
            ("[Retainer]", context.retainer),
            ("[Amount Due]", context.retainer),
            ("[Terms]", context.terms),
            ("[Payment Terms]", context.terms),
            ("[Package Description and Contents]", context.quoteDetails),
            ("[Quote Details]", context.quoteDetails),
            ("[Details]", context.quoteDetails),
            ("[Date Signed]", context.dateSigned),
            ("[Agreement Created Date]", context.agreementCreatedDate),
        ]
    }
}
