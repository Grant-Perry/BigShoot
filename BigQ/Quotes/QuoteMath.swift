import Foundation

nonisolated enum QuoteMath {
    static func nextNumber(among numbers: [String]) -> String {
        let highest = numbers.compactMap { Int($0) }.max() ?? 0
        return String(highest + 1)
    }

    static func recalculate(_ quote: Quote) {
        let subtotal = quote.lines.reduce(Decimal.zero) { partial, line in
            partial + line.lineTotal
        }
        quote.total = InvoiceMath.total(
            subtotal: subtotal,
            tax: quote.tax,
            discount: quote.discount,
            shipping: quote.shipping
        )
    }

    /// Full quote line-item copy for `[Quote Details]` — packages, descriptions, amounts.
    @MainActor
    static func agreementDetailsHTML(for quote: Quote) -> String {
        agreementDetailsBlocks(for: quote).joined(separator: "<br><br>")
    }

    /// Live-fill path for the quote editor (draft lines, no persisted `Quote` yet).
    @MainActor
    static func agreementDetailsHTML(
        lines: [DraftLine],
        tax: Decimal,
        discount: Decimal,
        shipping: Decimal,
        total: Decimal
    ) -> String {
        agreementDetailsBlocks(
            lines: lines.map { ($0.name, $0.detail, $0.quantity, $0.lineTotal) },
            tax: tax,
            discount: discount,
            shipping: shipping,
            total: total
        ).joined(separator: "<br><br>")
    }

    @MainActor
    static func agreementDetailsBlocks(for quote: Quote) -> [String] {
        agreementDetailsBlocks(
            lines: quote.sortedLines.map { ($0.name, $0.detail, $0.quantity, $0.lineTotal) },
            tax: quote.tax,
            discount: quote.discount,
            shipping: quote.shipping,
            total: quote.total
        )
    }

    @MainActor
    private static func agreementDetailsBlocks(
        lines: [(name: String, detail: String, quantity: Decimal, lineTotal: Decimal)],
        tax: Decimal,
        discount: Decimal,
        shipping: Decimal,
        total: Decimal
    ) -> [String] {
        let named = lines.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !named.isEmpty else { return [] }

        var blocks = named.map { agreementLineBlock(name: $0.name, detail: $0.detail, quantity: $0.quantity, lineTotal: $0.lineTotal) }

        var totals: [String] = []
        let subtotal = named.reduce(Decimal.zero) { $0 + $1.lineTotal }
        totals.append("Subtotal: \(StudioMoney.string(subtotal))")
        if discount > 0 {
            totals.append("Discount: −\(StudioMoney.string(discount))")
        }
        if shipping > 0 {
            totals.append("Shipping: \(StudioMoney.string(shipping))")
        }
        if tax > 0 {
            totals.append("Tax: \(StudioMoney.string(tax))")
        }
        totals.append("Total: \(StudioMoney.string(total))")
        blocks.append(totals.joined(separator: "<br>"))
        return blocks
    }

    @MainActor
    private static func agreementLineBlock(
        name: String,
        detail: String,
        quantity: Decimal,
        lineTotal: Decimal
    ) -> String {
        let trimmedName = escape(name.trimmingCharacters(in: .whitespacesAndNewlines))
        let money = StudioMoney.string(lineTotal)
        let headline: String
        if quantity == 1 {
            headline = "\(trimmedName) — \(money)"
        } else {
            let qtyText = quantity.formatted(.number.precision(.fractionLength(0...2)))
            headline = "\(trimmedName) × \(qtyText) — \(money)"
        }
        let trimmedDetail = detail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !trimmedDetail.isEmpty else { return headline }
        let detailHTML = escape(trimmedDetail).replacingOccurrences(of: "\n", with: "<br>")
        return "\(headline)<br>\(detailHTML)"
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
