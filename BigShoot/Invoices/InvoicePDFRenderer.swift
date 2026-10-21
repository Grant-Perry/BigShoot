import AppKit
import Foundation

enum InvoicePDFRenderer {
    static let pageSize = CGSize(width: 612, height: 792)

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
        let margin: CGFloat = 54
        var y: CGFloat = 54
        let gold = NSColor(calibratedRed: 0.80, green: 0.65, blue: 0.35, alpha: 1)
        let ink = NSColor(calibratedWhite: 0.12, alpha: 1)
        let muted = NSColor(calibratedWhite: 0.38, alpha: 1)

        draw("Grant & Deb Photography", at: margin, y: &y, width: 320, font: system(22), color: ink, context: context)
        y += 4
        draw("Studio invoice", at: margin, y: &y, width: 320, font: system(12), color: muted, context: context)

        let number = invoice.displayNumber
        draw(
            number,
            at: media.width - margin - 180,
            y: 54,
            width: 180,
            font: system(22),
            color: ink,
            alignment: .right,
            context: context
        )
        draw(
            invoice.displayStatus.title,
            at: media.width - margin - 180,
            y: 82,
            width: 180,
            font: system(12),
            color: muted,
            alignment: .right,
            context: context
        )

        y += 10
        context.setStrokeColor(gold.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: margin, y: media.height - y))
        context.addLine(to: CGPoint(x: media.width - margin, y: media.height - y))
        context.strokePath()
        y += 22

        draw("Bill to", at: margin, y: &y, width: 240, font: system(11, weight: .semibold), color: muted, context: context)
        draw(invoice.clientName, at: margin, y: &y, width: 260, font: system(14, weight: .semibold), color: ink, context: context)
        if let email = invoice.contact?.email, !email.isEmpty {
            draw(email, at: margin, y: &y, width: 260, font: system(11), color: muted, context: context)
        }
        if let job = invoice.job?.displayName {
            draw(job, at: margin, y: &y, width: 260, font: system(11), color: muted, context: context)
        }

        let metaX = media.width - margin - 200
        var metaY: CGFloat = 128
        meta("Invoice date", StudioDay.string(invoice.invoiceDate), x: metaX, y: &metaY, context: context, ink: ink, muted: muted)
        meta("Due", StudioDay.string(invoice.dueDate), x: metaX, y: &metaY, context: context, ink: ink, muted: muted)
        if let paid = invoice.paidDate {
            meta("Paid", StudioDay.string(paid), x: metaX, y: &metaY, context: context, ink: ink, muted: muted)
        }

        y = max(y, metaY) + 18
        drawColumns(y: y, media: media, margin: margin, font: system(10, weight: .semibold), color: muted, context: context, values: ("Item", "Qty", "Price", "Amount"))
        y += 18

        var drawn = 0
        for line in invoice.sortedLines {
            let rowHeight: CGFloat = line.detail.isEmpty ? 22 : 36
            if y + rowHeight > pageSize.height - 220 { break }
            draw(line.name, at: margin, y: y, width: 280, font: system(12), color: ink, context: context)
            draw(plain(line.quantity), at: 360, y: y, width: 50, font: system(12), color: ink, alignment: .right, context: context)
            draw(StudioMoney.string(line.unitPrice), at: 420, y: y, width: 70, font: system(12), color: ink, alignment: .right, context: context)
            draw(StudioMoney.string(line.lineTotal), at: media.width - margin - 80, y: y, width: 80, font: system(12, weight: .semibold), color: ink, alignment: .right, context: context)
            if !line.detail.isEmpty {
                draw(line.detail, at: margin, y: y + 16, width: 280, font: system(10), color: muted, context: context)
            }
            y += rowHeight
            drawn += 1
        }
        let hidden = invoice.sortedLines.count - drawn
        if invoice.lines.isEmpty {
            draw("No line items were stored for this invoice.", at: margin, y: &y, width: 400, font: system(12), color: muted, context: context)
        } else if hidden > 0 {
            draw("\(hidden) more items are in BigShoot.", at: margin, y: &y, width: 400, font: system(11), color: muted, context: context)
        }

        var totalsY = media.height - 196
        totalRow("Tax", invoice.tax, y: &totalsY, media: media, margin: margin, ink: ink, muted: muted, context: context)
        totalRow("Total", invoice.total, y: &totalsY, media: media, margin: margin, ink: ink, muted: muted, context: context, emphasis: true)
        totalRow("Paid", invoice.amountPaid, y: &totalsY, media: media, margin: margin, ink: ink, muted: muted, context: context)
        totalRow("Balance", invoice.balance, y: &totalsY, media: media, margin: margin, ink: ink, muted: muted, context: context, emphasis: true)

        if !invoice.note.isEmpty {
            draw(invoice.note, at: margin, y: media.height - 180, width: 280, font: system(10), color: muted, context: context)
        }
        draw(
            "Thank you.",
            at: margin,
            y: media.height - 72,
            width: 200,
            font: system(14),
            color: ink,
            context: context
        )
    }

    private static func meta(_ label: String, _ value: String, x: CGFloat, y: inout CGFloat, context: CGContext, ink: NSColor, muted: NSColor) {
        draw(label, at: x, y: y, width: 80, font: system(10), color: muted, context: context)
        draw(value, at: x + 84, y: y, width: 116, font: system(11, weight: .medium), color: ink, alignment: .right, context: context)
        y += 16
    }

    private static func totalRow(
        _ label: String,
        _ amount: Decimal,
        y: inout CGFloat,
        media: CGRect,
        margin: CGFloat,
        ink: NSColor,
        muted: NSColor,
        context: CGContext,
        emphasis: Bool = false
    ) {
        draw(label, at: media.width - margin - 180, y: y, width: 80, font: system(11, weight: emphasis ? .semibold : .regular), color: muted, context: context)
        draw(StudioMoney.string(amount), at: media.width - margin - 90, y: y, width: 90, font: system(emphasis ? 13 : 11, weight: .semibold), color: ink, alignment: .right, context: context)
        y += emphasis ? 20 : 16
    }

    private static func drawColumns(
        y: CGFloat,
        media: CGRect,
        margin: CGFloat,
        font: NSFont,
        color: NSColor,
        context: CGContext,
        values: (String, String, String, String)
    ) {
        draw(values.0, at: margin, y: y, width: 200, font: font, color: color, context: context)
        draw(values.1, at: 360, y: y, width: 50, font: font, color: color, alignment: .right, context: context)
        draw(values.2, at: 420, y: y, width: 70, font: font, color: color, alignment: .right, context: context)
        draw(values.3, at: media.width - margin - 80, y: y, width: 80, font: font, color: color, alignment: .right, context: context)
    }

    private static func draw(
        _ text: String,
        at x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left,
        context: CGContext
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let height = font.pointSize + 6
        let rect = CGRect(x: x, y: pageSize.height - y - height, width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func draw(
        _ text: String,
        at x: CGFloat,
        y: inout CGFloat,
        width: CGFloat,
        font: NSFont,
        color: NSColor,
        context: CGContext
    ) {
        draw(text, at: x, y: y, width: width, font: font, color: color, context: context)
        y += font.pointSize + 8
    }

    private static func plain(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func system(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
}
