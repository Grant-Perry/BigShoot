import AppKit
import CoreText
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

    /// Agreement pages only — merged variables, no pricing sheet.
    static func renderAgreementOnly(_ quote: Quote) -> Data {
        guard quote.hasAgreement else { return Data() }
        return renderAgreement(quote)
    }

    private static func renderPricing(_ quote: Quote) -> Data {
        do {
            let schema = Schema(versionedSchema: StudioSchemaV12.self)
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
        let merged = AgreementMerge.resolve(
            quote.agreementHTML,
            with: AgreementMerge.context(
                contact: quote.contact,
                job: quote.job,
                studio: quote.studio,
                quote: quote
            )
        )
        let blocks = AgreementPDFLayout.blocks(
            mergedHTML: merged,
            agreementTitle: title,
            studioName: quote.studio?.name
        )
        let fieldLabels = blocks.compactMap { block -> String? in
            if case let .field(label, _) = block { return label }
            return nil
        }
        let fieldLabelFont = sans(11, weight: .semibold)
        let fieldColumn = AgreementPDFLayout.colonColumn(
            for: fieldLabels,
            font: fieldLabelFont,
            margin: margin
        )

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var media = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return Data() }

        let contentWidth = media.width - margin * 2
        var blockIndex = 0
        while blockIndex < blocks.count {
            context.beginPDFPage(nil)
            var y: CGFloat = 54
            paint("Agreement", x: margin, top: y, width: contentWidth, font: sans(9, weight: .semibold), color: mute, context: context)
            y += 18
            rule(x: margin, y: y, width: contentWidth, context: context)
            y += 20

            let pageStart = blockIndex
            while blockIndex < blocks.count {
                let block = blocks[blockIndex]
                let needed = blockHeight(block, contentWidth: contentWidth, fieldColumn: fieldColumn)
                if y + needed > pageSize.height - 54, blockIndex > pageStart { break }
                y = paint(block, top: y, contentWidth: contentWidth, fieldColumn: fieldColumn, context: context)
                blockIndex += 1
            }
            context.endPDFPage()
            if blockIndex == pageStart { break }
        }
        context.closePDF()
        return data as Data
    }

    private static func blockHeight(
        _ block: AgreementPDFLayout.Block,
        contentWidth: CGFloat,
        fieldColumn: (colonX: CGFloat, labelWidth: CGFloat)
    ) -> CGFloat {
        switch block {
        case .centeredHeadline(let text):
            return blockHeight(text, width: contentWidth, font: sans(24, weight: .bold)) + 6
        case .horizontalRule:
            return 14
        case .centeredSubhead(let text):
            return blockHeight(text, width: contentWidth, font: sans(16, weight: .semibold)) + 12
        case .field(_, let value):
            let valueWidth = margin + contentWidth - fieldColumn.colonX - 8
            let valueHeight = blockHeight(value, width: valueWidth, font: sans(11))
            return max(lineBox(sans(11, weight: .semibold)), valueHeight) + 4
        case .paragraph(let text):
            return blockHeight(text, width: contentWidth, font: sans(11)) + 10
        }
    }

    private static func paint(
        _ block: AgreementPDFLayout.Block,
        top: CGFloat,
        contentWidth: CGFloat,
        fieldColumn: (colonX: CGFloat, labelWidth: CGFloat),
        context: CGContext
    ) -> CGFloat {
        var y = top
        switch block {
        case .centeredHeadline(let text):
            let font = sans(24, weight: .bold)
            let height = blockHeight(text, width: contentWidth, font: font)
            paintBlock(text, x: margin, top: y, width: contentWidth, height: height, font: font, color: ink, alignment: .center, context: context)
            y += height + 6
        case .horizontalRule:
            y += 4
            rule(x: margin, y: y, width: contentWidth, context: context)
            y += 10
        case .centeredSubhead(let text):
            let font = sans(16, weight: .semibold)
            let height = blockHeight(text, width: contentWidth, font: font)
            paintBlock(text, x: margin, top: y, width: contentWidth, height: height, font: font, color: ink, alignment: .center, context: context)
            y += height + 12
        case .field(let label, let value):
            let labelFont = sans(11, weight: .semibold)
            let valueFont = sans(11)
            let valueWidth = margin + contentWidth - fieldColumn.colonX - 8
            let valueHeight = blockHeight(value, width: valueWidth, font: valueFont)
            let labelHeight = lineBox(labelFont)
            let row = max(labelHeight, valueHeight)
            // Keep the label on the first value line (Pay Details stack stays under values).
            paint(
                "\(label):",
                x: fieldColumn.colonX - fieldColumn.labelWidth,
                top: y,
                width: fieldColumn.labelWidth,
                font: labelFont,
                color: ink,
                alignment: .right,
                context: context
            )
            paintBlock(
                value,
                x: fieldColumn.colonX + 8,
                top: y,
                width: valueWidth,
                height: valueHeight,
                font: valueFont,
                color: ink,
                alignment: .left,
                context: context
            )
            y += row + 4
        case .paragraph(let text):
            let font = sans(11)
            let height = blockHeight(text, width: contentWidth, font: font)
            paintBlock(text, x: margin, top: y, width: contentWidth, height: height, font: font, color: ink, alignment: .left, context: context)
            y += height + 10
        }
        return y
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
        alignment: NSTextAlignment = .left,
        context: CGContext
    ) {
        let height = blockHeight(text, width: width, font: font)
        paintBlock(text, x: x, top: top, width: width, height: height, font: font, color: color, alignment: alignment, context: context)
    }

    private static func paintBlock(
        _ text: String,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        height: CGFloat,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left,
        context: CGContext
    ) {
        let attributed = attributedBlock(text, font: font, color: color, alignment: alignment)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let rect = CGRect(
            x: x,
            y: pageSize.height - top - height,
            width: width,
            height: height
        )
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        context.saveGState()
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private static func blockHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let attributed = attributedBlock(text, font: font, color: ink)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var fitRange = CFRange()
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            &fitRange
        )
        let line = ceil(abs(font.ascender) + abs(font.descender) + abs(font.leading))
        return max(ceil(suggested.height) + ceil(line * 0.35), line)
    }

    private static func attributedBlock(
        _ text: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 2
        style.paragraphSpacing = 0
        // Renders user bold / italic / underline markers; plain text passes straight through.
        return AgreementInlineStyle.attributed(text, font: font, attributes: [
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
    }

    private static func lineBox(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender)
    }

    private static func rule(x: CGFloat, y: CGFloat, width: CGFloat, context: CGContext) {
        context.setStrokeColor(gold.cgColor)
        context.setLineWidth(0.6)
        context.move(to: CGPoint(x: x, y: pageSize.height - y))
        context.addLine(to: CGPoint(x: x + width, y: pageSize.height - y))
        context.strokePath()
    }

    private static func sans(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
}
