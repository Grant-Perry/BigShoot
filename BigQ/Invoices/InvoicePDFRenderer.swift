import AppKit
import Foundation

enum InvoicePDFRenderer {
    static let pageSize = CGSize(width: 612, height: 792)

    private static let margin: CGFloat = 58
    private static let contactIndent: CGFloat = 15
    private static let ink = NSColor(calibratedWhite: 0.09, alpha: 1)
    private static let mute = NSColor(calibratedWhite: 0.40, alpha: 1)
    private static let gold = NSColor(calibratedRed: 0.80, green: 0.65, blue: 0.35, alpha: 1)
    private static let hairline = NSColor(calibratedWhite: 0.76, alpha: 1)

    static func render(_ invoice: Invoice) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var media = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return Data() }
        context.beginPDFPage(nil)
        draw(invoice, in: context, media: media)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private static func draw(_ invoice: Invoice, in context: CGContext, media: CGRect) {
        let contentWidth = media.width - margin * 2
        let right = media.width - margin
        let labels = LabelColumn(right: right)
        var y = drawMasthead(invoice, contentWidth: contentWidth, right: right, context: context)

        y += 16
        rule(x: margin, y: y, width: contentWidth, weight: 0.6, color: gold, context: context)
        y += 22

        y = drawParties(invoice, top: y, labels: labels, context: context)
        y += 22
        y = drawTable(invoice, top: y, right: right, labels: labels, context: context)
        drawFooter(invoice, context: context)
    }

    private static func drawFooter(_ invoice: Invoice, context: CGContext) {
        let font = sans(13, weight: .thin)
        let text = signOff(for: invoice)
        let width: CGFloat = 280
        let height = blockHeight(text, width: width, font: font)
        let top = pageSize.height - 40 - height
        paintBlock(text, x: margin, top: top, width: width, height: height, font: font, color: ink, context: context)
        if !invoice.note.isEmpty {
            paint(
                invoice.note,
                x: margin,
                top: top - 20,
                width: 250,
                font: sans(10),
                color: mute,
                context: context
            )
        }
    }

    private static func signOff(for invoice: Invoice) -> String {
        let trimmed = invoice.closing.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Thank you." : trimmed
    }

    private static func drawMasthead(
        _ invoice: Invoice,
        contentWidth: CGFloat,
        right: CGFloat,
        context: CGContext
    ) -> CGFloat {
        let numberColumn: CGFloat = 156
        let nameWidth = contentWidth - numberColumn - 24
        let studioName = invoice.studio?.displayName ?? "Studio"
        let nameFont = display(fitting: studioName, width: nameWidth, size: 26, floor: 18)
        let numberFont = display(24)
        let kickerFont = sans(9, weight: .semibold)
        let nameBox = lineBox(nameFont)
        let numberBox = lineBox(numberFont)
        let kickerBox = lineBox(kickerFont)

        let lift = max(0, 40 - (54 + nameBox - numberBox - kickerBox - 5))
        let nameTop = 54 + lift
        let numberTop = nameTop + nameBox - numberBox
        let kickerTop = numberTop - kickerBox - 5

        paint(studioName, x: margin, top: nameTop, width: nameWidth, font: nameFont, color: ink, context: context)
        paint(
            "Invoice",
            x: right - numberColumn,
            top: kickerTop,
            width: numberColumn,
            font: kickerFont,
            color: mute,
            alignment: .right,
            kern: 1.5,
            context: context
        )
        paint(
            invoice.displayNumber,
            x: right - numberColumn,
            top: numberTop,
            width: numberColumn,
            font: numberFont,
            color: ink,
            alignment: .right,
            context: context
        )

        var y = nameTop + nameBox + 9
        let contact = contactLines(invoice.studio).prefix(8)
        let contactFont = sans(10.5)
        let contactBox = lineBox(contactFont)
        for line in contact {
            paint(
                line,
                x: margin + contactIndent,
                top: y,
                width: nameWidth - contactIndent,
                font: contactFont,
                color: mute,
                context: context
            )
            y += contactBox + 1
        }
        if contact.isEmpty == false {
            y += 2
        }
        return y
    }

    private static func drawParties(_ invoice: Invoice, top: CGFloat, labels: LabelColumn, context: CGContext) -> CGFloat {
        let labelFont = fieldLabel
        let labelBox = lineBox(labelFont)
        var y = top
        paint("Bill to:", x: margin, top: y, width: 240, font: labelFont, color: mute, context: context)

        var metaY = top
        labeled("Invoice date", StudioDay.string(invoice.invoiceDate), column: labels, y: &metaY, valueFont: figures(11, weight: .medium), context: context)
        labeled("Due", StudioDay.string(invoice.dueDate), column: labels, y: &metaY, valueFont: figures(11, weight: .medium), context: context)
        if let paid = invoice.paidDate {
            labeled("Paid", StudioDay.string(paid), column: labels, y: &metaY, valueFont: figures(11, weight: .medium), context: context)
        }

        y += labelBox + 5
        let clientFont = display(17)
        paint(invoice.clientName, x: margin, top: y, width: 270, font: clientFont, color: ink, context: context)
        y += lineBox(clientFont) + 3

        if let email = invoice.contact?.email, !email.isEmpty {
            let emailFont = sans(10.5)
            paint(email, x: margin, top: y, width: 270, font: emailFont, color: mute, context: context)
            y += lineBox(emailFont) + 1
        }
        return max(y, metaY)
    }

    private static func drawTable(_ invoice: Invoice, top: CGFloat, right: CGFloat, labels: LabelColumn, context: CGContext) -> CGFloat {
        let columns = Columns(right: right)
        let headerFont = sans(9, weight: .semibold)
        let headerBox = lineBox(headerFont)
        var y = top
        if let job = invoice.job?.displayName {
            let jobFont = sans(13, weight: .semibold)
            paint("Job: \(job)", x: margin, top: y, width: right - margin, font: jobFont, color: ink, context: context)
            y += lineBox(jobFont) + 10
        }
        paint("Item", x: columns.itemX, top: y, width: columns.itemWidth, font: headerFont, color: mute, kern: 0.4, context: context)
        paint("Qty", x: columns.qtyX, top: y, width: columns.qtyWidth, font: headerFont, color: mute, alignment: .right, context: context)
        paint("Price", x: columns.priceX, top: y, width: columns.priceWidth, font: headerFont, color: mute, alignment: .right, context: context)
        paint("Amount", x: columns.amountX, top: y, width: columns.amountWidth, font: headerFont, color: mute, alignment: .right, context: context)
        y += headerBox + 4
        rule(x: margin, y: y, width: right - margin, weight: 0.4, color: hairline, context: context)
        y += 9

        let lineLimit = pageSize.height - 210
        var drawn = 0
        let bodyFont = sans(12)
        let bodyBox = lineBox(bodyFont)
        let detailFont = sans(10)
        for line in invoice.sortedLines {
            let rowHeight = line.detail.isEmpty ? bodyBox + 8 : bodyBox + lineBox(detailFont) + 12
            if y + rowHeight > lineLimit { break }
            paint(line.name, x: columns.itemX, top: y, width: columns.itemWidth, font: bodyFont, color: ink, context: context)
            paint(plain(line.quantity), x: columns.qtyX, top: y, width: columns.qtyWidth, font: figures(12), color: ink, alignment: .right, context: context)
            paint(StudioMoney.string(line.unitPrice), x: columns.priceX, top: y, width: columns.priceWidth, font: figures(12), color: ink, alignment: .right, context: context)
            paint(StudioMoney.string(line.lineTotal), x: columns.amountX, top: y, width: columns.amountWidth, font: figures(12, weight: .semibold), color: ink, alignment: .right, context: context)
            if !line.detail.isEmpty {
                paint(line.detail, x: columns.itemX, top: y + bodyBox + 1, width: columns.itemWidth, font: detailFont, color: mute, context: context)
            }
            y += rowHeight
            drawn += 1
        }

        let hidden = invoice.sortedLines.count - drawn
        if invoice.lines.isEmpty {
            let font = sans(12)
            paint("No line items were stored for this invoice.", x: margin, top: y, width: 360, font: font, color: mute, context: context)
            y += lineBox(font) + 4
        } else if hidden > 0 {
            let font = sans(10.5)
            paint("\(hidden) more items are in BigQ.", x: margin, top: y, width: 360, font: font, color: mute, context: context)
            y += lineBox(font) + 4
        }

        y += 16
        return drawTotals(invoice, top: y, labels: labels, context: context)
    }

    private static func drawTotals(_ invoice: Invoice, top: CGFloat, labels: LabelColumn, context: CGContext) -> CGFloat {
        var y = top
        labeled("Tax", StudioMoney.string(invoice.tax), column: labels, y: &y, valueFont: figures(11), gapAfter: 3, context: context)
        labeled("Total", StudioMoney.string(invoice.total), column: labels, y: &y, valueFont: figures(12, weight: .semibold), gapAfter: 5, context: context)
        labeled("Paid", StudioMoney.string(invoice.amountPaid), column: labels, y: &y, valueFont: figures(11), gapAfter: 3, context: context)
        y += 6
        rule(
            x: labels.colonX - labels.labelWidth,
            y: y,
            width: labels.valueRight - (labels.colonX - labels.labelWidth),
            weight: 0.5,
            color: ink.withAlphaComponent(0.28),
            context: context
        )
        y += 8
        let dueFont = figures(16, weight: .semibold)
        let box = lineBox(dueFont)
        let labelTop = y + (box - lineBox(fieldLabel)) / 2
        paint("Balance:", x: labels.colonX - labels.labelWidth, top: labelTop, width: labels.labelWidth, font: fieldLabel, color: mute, alignment: .right, context: context)
        paint(StudioMoney.string(invoice.balance), x: labels.valueRight - labels.valueWidth, top: y, width: labels.valueWidth, font: dueFont, color: ink, alignment: .right, context: context)
        return y + box
    }

    /// Field labels share one font so every colon lands on the same edge.
    private static var fieldLabel: NSFont { sans(10, weight: .medium) }

    private static func labeled(
        _ label: String,
        _ value: String,
        column: LabelColumn,
        y: inout CGFloat,
        valueFont: NSFont,
        gapAfter: CGFloat = 6,
        context: CGContext
    ) {
        let box = max(lineBox(fieldLabel), lineBox(valueFont))
        let labelTop = y + (box - lineBox(fieldLabel)) / 2
        let valueTop = y + (box - lineBox(valueFont)) / 2
        let text = label.hasSuffix(":") ? label : label + ":"
        paint(text, x: column.colonX - column.labelWidth, top: labelTop, width: column.labelWidth, font: fieldLabel, color: mute, alignment: .right, context: context)
        paint(value, x: column.valueRight - column.valueWidth, top: valueTop, width: column.valueWidth, font: valueFont, color: ink, alignment: .right, context: context)
        y += box + gapAfter
    }

    private static func contactLines(_ studio: StudioBrand?) -> [String] {
        guard let studio else { return [] }
        return [studio.email, studio.phone, studio.address].flatMap(splitLines)
    }

    private static func splitLines(_ value: String) -> [String] {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func rule(x: CGFloat, y: CGFloat, width: CGFloat, weight: CGFloat, color: NSColor, context: CGContext) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(weight)
        context.move(to: CGPoint(x: x, y: pageSize.height - y))
        context.addLine(to: CGPoint(x: x + width, y: pageSize.height - y))
        context.strokePath()
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
        ).boundingRect(with: CGSize(width: width, height: 80), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return min(max(ceil(bounds.height), lineBox(font)), 54)
    }

    private static func paint(
        _ text: String,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left,
        kern: CGFloat = 0,
        context: CGContext
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        if kern != 0 {
            attributes[.kern] = kern
        }
        let height = lineBox(font) + 1
        let rect = CGRect(x: x, y: pageSize.height - top - height, width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func lineBox(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender)
    }

    private static func measure(_ text: String, font: NSFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    private static func plain(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func display(fitting text: String, width: CGFloat, size: CGFloat, floor: CGFloat) -> NSFont {
        var size = size
        var font = display(size)
        while size > floor && measure(text, font: font) > width {
            size -= 0.5
            font = display(size)
        }
        return font
    }

    private static func display(_ size: CGFloat) -> NSFont {
        sans(size, weight: .thin)
    }

    private static func sans(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    private static func figures(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    private struct Columns {
        var itemX: CGFloat
        var itemWidth: CGFloat
        var qtyX: CGFloat
        var qtyWidth: CGFloat
        var priceX: CGFloat
        var priceWidth: CGFloat
        var amountX: CGFloat
        var amountWidth: CGFloat
        init(right: CGFloat) {
            amountWidth = 118
            priceWidth = 78
            qtyWidth = 36
            amountX = right - amountWidth
            priceX = amountX - 14 - priceWidth
            qtyX = priceX - 12 - qtyWidth
            itemX = margin
            itemWidth = qtyX - 18 - itemX
        }
    }

    /// Right edge of every field label is the colon. Dates and totals share it.
    private struct LabelColumn {
        var colonX: CGFloat
        var valueRight: CGFloat
        var labelWidth: CGFloat
        var valueWidth: CGFloat

        init(right: CGFloat) {
            let font = InvoicePDFRenderer.fieldLabel
            let widest = ["Invoice date:", "Balance:", "Bill to:"].map { InvoicePDFRenderer.measure($0, font: font) }.max() ?? 72
            valueWidth = 118
            valueRight = right
            colonX = right - valueWidth - 12
            labelWidth = ceil(widest) + 4
        }
    }
}
