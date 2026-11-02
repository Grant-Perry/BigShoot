import AppKit
import Foundation
import PDFKit
import SwiftData

enum QuotePDFRenderer {
    private static let pageSize = InvoicePDFRenderer.pageSize
    private static let margin: CGFloat = 58
    private static let ink = NSColor(calibratedWhite: 0.09, alpha: 1)
    private static let mute = NSColor(calibratedWhite: 0.40, alpha: 1)
    private static let gold = NSColor(calibratedRed: 0.80, green: 0.65, blue: 0.35, alpha: 1)

    static func render(_ quote: Quote) -> Data {
        let pricing = renderPricing(quote)
        guard quote.hasAgreement else { return pricing }
        let agreement = renderAgreement(quote)
        return merge(pricing, agreement) ?? pricing
    }

    private static func renderPricing(_ quote: Quote) -> Data {
        do {
            let schema = Schema(versionedSchema: StudioSchemaV10.self)
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let invoice = Invoice(
                number: quote.number,
                invoiceDate: quote.quoteDate,
                dueDate: quote.validUntil,
                status: .draft,
                tax: quote.tax,
                taxRate: quote.taxRate ?? 0,
                taxScheduleName: quote.taxScheduleName ?? "",
                invoiceTaxable: quote.invoiceTaxable,
                discount: quote.discount,
                shipping: quote.shipping,
                billToName: quote.billToName,
                note: quote.note,
                closing: quote.closing
            )
            context.insert(invoice)
            if let studio = quote.studio {
                let copy = StudioBrand(
                    name: studio.name,
                    email: studio.email,
                    phone: studio.phone,
                    address: studio.address,
                    isPrimary: studio.isPrimary,
                    logoImageData: studio.logoImageData,
                    logoImageSourceData: studio.logoImageSourceData
                )
                context.insert(copy)
                invoice.studio = copy
            }
            if let contact = quote.contact {
                let copy = Contact(fullName: contact.displayName, email: contact.email)
                context.insert(copy)
                invoice.contact = copy
            }
            if let job = quote.job {
                let copy = Job(name: job.name, eventDate: job.eventDate, jobType: job.jobType)
                context.insert(copy)
                invoice.job = copy
            }
            for line in quote.sortedLines {
                let copy = InvoiceLine(
                    name: line.name,
                    detail: line.detail,
                    quantity: line.quantity,
                    unitPrice: line.unitPrice,
                    position: line.position,
                    taxable: line.taxable ?? false
                )
                copy.invoice = invoice
                context.insert(copy)
            }
            InvoiceMath.recalculate(invoice)
            return InvoicePDFRenderer.render(
                invoice,
                documentTitle: "Quote",
                dateLabel: "Quote date",
                dueLabel: "Valid until"
            )
        } catch {
            DebugPrint(mode: .error, "Quote PDF pricing failed: \(error.localizedDescription)")
            return Data()
        }
    }

    private static func renderAgreement(_ quote: Quote) -> Data {
        let title = quote.agreementTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ContractDocument.plain(quote.agreementHTML)
        var paragraphs = body.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        paragraphs.insert(title.isEmpty ? "Agreement" : title, at: 0)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var media = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return Data() }

        var index = 0
        while index < paragraphs.count {
            context.beginPDFPage(nil)
            var y: CGFloat = 54
            let contentWidth = media.width - margin * 2
            paint("Agreement", x: margin, top: y, width: contentWidth, font: sans(9, weight: .semibold), color: mute, context: context)
            y += 18
            rule(x: margin, y: y, width: contentWidth, context: context)
            y += 20

            let pageStart = index
            while index < paragraphs.count {
                let text = paragraphs[index]
                let isTitle = index == 0
                let font = isTitle ? display(18) : sans(11)
                let height = blockHeight(text, width: contentWidth, font: font)
                if y + height > pageSize.height - 54, index > pageStart { break }
                paintBlock(text, x: margin, top: y, width: contentWidth, height: height, font: font, color: ink, context: context)
                y += height + (isTitle ? 16 : 12)
                index += 1
            }
            context.endPDFPage()
            if index == pageStart { break }
        }
        context.closePDF()
        return data as Data
    }

    private static func merge(_ first: Data, _ second: Data) -> Data? {
        guard let left = PDFDocument(data: first), let right = PDFDocument(data: second) else {
            return first
        }
        let merged = PDFDocument()
        var cursor = 0
        for document in [left, right] {
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                merged.insert(page, at: cursor)
                cursor += 1
            }
        }
        return merged.dataRepresentation()
    }

    private static func paint(
        _ text: String,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        font: NSFont,
        color: NSColor,
        context: CGContext
    ) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let height = ceil(font.ascender - font.descender) + 1
        let rect = CGRect(x: x, y: pageSize.height - top - height, width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func paintBlock(
        _ text: String,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        height: CGFloat,
        font: NSFont,
        color: NSColor,
        context: CGContext
    ) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let rect = CGRect(x: x, y: pageSize.height - top - height, width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func blockHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let bounds = NSAttributedString(
            string: text,
            attributes: [.font: font, .paragraphStyle: style]
        ).boundingRect(
            with: CGSize(width: width, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return max(ceil(bounds.height), ceil(font.ascender - font.descender))
    }

    private static func rule(x: CGFloat, y: CGFloat, width: CGFloat, context: CGContext) {
        context.setStrokeColor(gold.cgColor)
        context.setLineWidth(0.6)
        context.move(to: CGPoint(x: x, y: pageSize.height - y))
        context.addLine(to: CGPoint(x: x + width, y: pageSize.height - y))
        context.strokePath()
    }

    private static func display(_ size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .thin)
    }

    private static func sans(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
}
