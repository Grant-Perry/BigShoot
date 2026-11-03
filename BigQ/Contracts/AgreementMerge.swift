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
        // Job contact is always the agreement client when the job has one.
        let client = job?.contact ?? contact
        if let client {
            ctx.clientName = client.displayName
            ctx.clientFirstName = client.firstName
            ctx.clientLastName = client.lastName
            ctx.clientEmail = client.email
            ctx.clientPhone = client.phone
            ctx.clientCompany = client.companyName
            ctx.clientAddress = client.address
            ctx.primaryContactName = client.displayName
        }
        if let job {
            ctx.jobName = job.displayName
            ctx.jobType = job.jobType
            ctx.jobStatus = job.status.replacingOccurrences(of: "_", with: " ")
            ctx.eventDate = StudioDay.string(job.eventDate)
            if ctx.primaryContactName.isEmpty {
                ctx.primaryContactName = job.contact?.displayName ?? ""
            }
        }
        if let studio {
            ctx.studioName = studio.displayName
            ctx.studioEmail = studio.email
            ctx.studioPhone = studio.phone
            ctx.studioAddress = studio.address
        }
        if let quote {
            ctx.quoteNumber = quote.displayNumber
            ctx.quoteDate = StudioDay.string(quote.quoteDate)
            ctx.validUntil = StudioDay.string(quote.validUntil)
            let subtotal = quote.lines.reduce(Decimal.zero) { $0 + $1.lineTotal }
            ctx.subtotal = StudioMoney.string(subtotal)
            ctx.totalAmount = StudioMoney.string(quote.total)
            ctx.totalTax = StudioMoney.string(quote.tax)
            ctx.totalDiscount = StudioMoney.string(quote.discount)
            ctx.remainingBalance = StudioMoney.string(quote.total)
            ctx.terms = QuotePaymentSchedule.agreementTermsHTML(for: quote)
            ctx.quoteDetails = QuoteMath.agreementDetailsHTML(for: quote)
            ctx.dateSigned = StudioDay.string(quote.signedAt)
            // Only fall back to quote bill-to when the job has no client on file.
            if ctx.clientName.isEmpty { ctx.clientName = quote.clientName }
            if ctx.clientAddress.isEmpty {
                ctx.clientAddress = (job?.contact ?? quote.contact)?.address ?? ""
            }
        }
        // Job contracts (and quotes with no schedule yet) pull `[Terms]` from the job.
        if ctx.terms.isEmpty, let job {
            ctx.terms = QuotePaymentSchedule.agreementTermsHTML(for: job)
        }
        ctx.agreementCreatedDate = StudioDay.string(now)
        return ctx
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
            ("[Company Name]", context.clientCompany.isEmpty ? context.studioName : context.clientCompany),
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
