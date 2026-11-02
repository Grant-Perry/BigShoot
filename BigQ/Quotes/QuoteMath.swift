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
}
