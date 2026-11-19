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

    static func render(_ quote: Quote, includeAgreement: Bool = true) -> Data {
        let pricing = renderPricing(quote)
        guard includeAgreement, quote.hasAgreement else { return pricing }
        let agreement = renderAgreement(quote)
        guard let merged = merge(pricing, agreement) else { return pricing }
        return PDFFormPatcher.patch(merged)
    }

    /// Agreement pages only — merged variables, no pricing sheet.
    static func renderAgreementOnly(_ quote: Quote) -> Data {
        guard quote.hasAgreement else { return Data() }
        return PDFFormPatcher.patch(renderAgreement(quote))
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
                dueLabel: "Valid until",
                numberSize: 14,
                schedule: scheduleRows(quote, total: invoice.total)
            )
        } catch {
            DebugPrint(mode: .error, "Quote PDF pricing failed: \(error.localizedDescription)")
            return Data()
        }
    }

    /// The quote's payment terms resolved to amounts and due dates for the pricing page.
    private static func scheduleRows(_ quote: Quote, total: Decimal) -> [InvoicePDFRenderer.ScheduleRow] {
        guard quote.paymentScheduleMode != .none else { return [] }
        var terms = quote.sortedPaymentTerms.map { term in
            DraftPaymentTerm(
                title: term.title,
                amountMode: term.amountMode,
                percent: term.percent,
                fixedAmount: term.fixedAmount,
                dueMode: term.dueMode,
                daysBeforeEvent: term.daysBeforeEvent,
                fixedDueDate: term.fixedDueDate ?? .now,
                amount: term.amount
            )
        }
        guard !terms.isEmpty else { return [] }
        QuotePaymentSchedule.recalculate(&terms, total: total)
        let eventDate = quote.job?.eventDate
        return terms.enumerated().map { index, term in
            let title = term.title.trimmingCharacters(in: .whitespacesAndNewlines)
            // The label already says when; the middle column only carries the date.
            let due: String
            switch term.dueMode {
            case .signature:
                due = ""
            case .daysBeforeEvent:
                due = QuotePaymentSchedule.resolveDue(term, signatureDate: nil, eventDate: eventDate)
                    .map { StudioDay.string($0) } ?? ""
            case .fixedDate:
                due = StudioDay.string(term.fixedDueDate)
            }
            return InvoicePDFRenderer.ScheduleRow(
                label: title.isEmpty ? "Payment \(index + 1)" : title,
                due: due,
                amount: StudioMoney.string(term.amount)
            )
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
        var signaturePainted = false
        var pageNumber = -1
        var signatureFields: [(name: String, page: Int, rect: CGRect)] = []
        let signatureHeight: CGFloat = 150
        while blockIndex < blocks.count || !signaturePainted {
            context.beginPDFPage(nil)
            pageNumber += 1
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
            if blockIndex == blocks.count, !signaturePainted, y + signatureHeight <= pageSize.height - 54 || blockIndex == pageStart {
                let fields = paintSignatures(quote, top: y + 16, contentWidth: contentWidth, context: context)
                signatureFields = fields.map { ($0.name, pageNumber, $0.rect) }
                signaturePainted = true
            }
            context.endPDFPage()
            if blockIndex == pageStart, !signaturePainted { break }
        }
        context.closePDF()
        return addSignatureFields(signatureFields, to: data as Data)
    }

    /// Fillable text fields sitting on the signature and date lines, so the client can type instead of printing.
    private static func addSignatureFields(_ fields: [(name: String, page: Int, rect: CGRect)], to data: Data) -> Data {
        guard !fields.isEmpty, let document = PDFDocument(data: data) else { return data }
        for field in fields {
            guard let page = document.page(at: field.page) else { continue }
            // rect is top-based; PDF space is bottom-up.
            let bounds = CGRect(
                x: field.rect.minX,
                y: pageSize.height - field.rect.maxY,
                width: field.rect.width,
                height: field.rect.height
            )
            let widget = PDFAnnotation(bounds: bounds, forType: .widget, withProperties: nil)
            widget.widgetFieldType = .text
            widget.fieldName = field.name
            widget.isMultiline = false
            widget.isReadOnly = false
            widget.widgetStringValue = ""
            // Base-14 Helvetica only: the system UI font name isn't a valid PDF font and makes the field reject typing.
            widget.font = NSFont(name: "Helvetica", size: field.name.hasSuffix("Signature") ? 14 : 11)
            widget.maximumLength = field.name.hasSuffix("Signature") ? 120 : 24
            widget.fontColor = ink
            widget.backgroundColor = gold.withAlphaComponent(0.12)
            widget.border = PDFBorder()
            widget.border?.lineWidth = 0
            page.addAnnotation(widget)
        }
        return document.dataRepresentation() ?? data
    }

    /// Client and studio signature lines so a printed copy can be signed by hand or filled in on screen.
    private static func paintSignatures(
        _ quote: Quote,
        top: CGFloat,
        contentWidth: CGFloat,
        context: CGContext
    ) -> [(name: String, rect: CGRect)] {
        var fields: [(name: String, rect: CGRect)] = []
        var y = top
        paint(
            "By signature below, the parties agree to the terms of this Agreement.",
            x: margin, top: y, width: contentWidth, font: sans(11), color: ink, context: context
        )
        y += 58
        let gap: CGFloat = 40
        let columnWidth = (contentWidth - gap) / 2
        let columns: [(role: String, name: String)] = [
            ("Client", quote.clientName),
            ("Studio", quote.studio?.displayName ?? "Studio")
        ]
        // Captions end in ":" and right-align to one colon edge per column, so "Date:" lines up under "… signature:".
        let captionFont = sans(9, weight: .semibold)
        let captionWidth = ceil(columns.map {
            NSAttributedString(string: "\($0.role) signature:", attributes: [.font: captionFont]).size().width
        }.max() ?? 0) + 2
        for (index, column) in columns.enumerated() {
            let x = margin + CGFloat(index) * (columnWidth + gap)
            let key = column.role.lowercased()
            fields.append(("\(key)Signature", CGRect(x: x, y: y - 28, width: columnWidth, height: 26)))
            fields.append(("\(key)Date", CGRect(x: x, y: y + 64 - 20, width: columnWidth * 0.6, height: 18)))
            rule(x: x, y: y, width: columnWidth, context: context)
            paint("\(column.role) signature:", x: x, top: y + 4, width: captionWidth, font: captionFont, color: mute, alignment: .right, context: context)
            paint(column.name, x: x, top: y + 20, width: columnWidth, font: sans(11), color: ink, context: context)
            let dateY = y + 64
            rule(x: x, y: dateY, width: columnWidth * 0.6, context: context)
            paint("Date:", x: x, top: dateY + 4, width: captionWidth, font: captionFont, color: mute, alignment: .right, context: context)
        }
        return fields
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
