import Darwin
import Foundation

enum PayLinkAmount {
    /// The next unpaid scheduled amount, or the whole balance when there is no schedule.
    static func forQuote(_ quote: Quote) -> Decimal {
        if let due = quote.sortedPaymentTerms.first(where: { $0.amount > 0 })?.amount {
            return due
        }
        return quote.total
    }

    static func forInvoice(_ invoice: Invoice) -> Decimal {
        let open = invoice.schedule
            .filter { $0.balance > 0 }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        if let due = open.first?.balance, due > 0 {
            return due
        }
        return invoice.balance
    }
}

enum PayMoney {
    /// Two-decimal US amount for the pay service. No currency sign, no grouping.
    static func wire(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? "0.00"
    }

    static func decimal(_ text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}

struct PayLinkPayment: Decodable, Equatable, Sendable {
    var transactionId: String
    var amount: String
    var cardLabel: String
    var paidAt: String

    var chargedAmount: Decimal? { PayMoney.decimal(amount) }

    var paidDate: Date? {
        guard !paidAt.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: paidAt) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: paidAt)
    }
}

struct PayLinkSnapshot: Decodable, Equatable, Sendable {
    var token: String
    var url: String
    var invoiceId: String
    var number: String
    var amount: String
    var billToName: String
    var studioName: String
    var status: String
    var transactionId: String
    var cardLabel: String
    var paidAt: String
    var failureMessage: String
    var payments: [PayLinkPayment]?

    var isPaid: Bool { status == "paid" }

    var recordedPayments: [PayLinkPayment] {
        if let payments, !payments.isEmpty { return payments }
        guard !transactionId.isEmpty, let parsed = PayMoney.decimal(amount), parsed > 0 else { return [] }
        return [PayLinkPayment(transactionId: transactionId, amount: amount, cardLabel: cardLabel, paidAt: paidAt)]
    }

    var paidDate: Date? {
        guard !paidAt.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: paidAt) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: paidAt)
    }
}

enum PayLinkError: LocalizedError {
    case notConfigured
    case server(String)
    case unreachable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Card payments aren’t set up on this Mac."
        case .server(let message):
            message
        case .unreachable:
            "Couldn’t reach the pay service."
        }
    }
}

/// Reads the studio key. The sandbox only allows a few paths under the home folder.
enum PayStudioKey {
    static func load() -> String? {
        for url in candidates {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static var candidates: [URL] {
        var urls = [
            URL(fileURLWithPath: "/Users/gp./Xcode/BigQ/shootq-export/pay-studio-key"),
            URL(fileURLWithPath: "/Users/gp./Xcode/BigQ/pay-studio-key"),
            URL(fileURLWithPath: "/Users/gp./Xcode/BigQ/.pay-studio-key"),
        ]
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            let home = URL(fileURLWithPath: String(cString: dir), isDirectory: true)
            urls.append(home.appending(path: "Xcode/BigQ/shootq-export/pay-studio-key", directoryHint: .notDirectory))
            urls.append(home.appending(path: "Xcode/BigQ/pay-studio-key", directoryHint: .notDirectory))
        }
        return urls
    }
}

struct PayAPI: Sendable {
    var baseURL: URL
    var studioKey: String
    var session: URLSession = .shared

    static let liveBase = URL(string: "https://bigq-pay.web.app")!

    func publish(
        invoiceId: String,
        number: String,
        amount: String,
        billToName: String,
        studioName: String
    ) async throws -> PayLinkSnapshot {
        try await send(
            path: "/api/links",
            method: "POST",
            body: [
                "invoiceId": invoiceId,
                "number": number,
                "amount": amount,
                "billToName": billToName,
                "studioName": studioName,
            ],
            authorized: true
        )
    }

    func status(invoiceId: String) async throws -> PayLinkSnapshot {
        try await send(
            path: "/api/invoices/\(invoiceId)",
            method: "GET",
            body: nil,
            authorized: true
        )
    }

    private func send(
        path: String,
        method: String,
        body: [String: String]?,
        authorized: Bool
    ) async throws -> PayLinkSnapshot {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            request.setValue("Bearer \(studioKey)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PayLinkError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 {
            throw PayLinkError.server("No pay link yet.")
        }
        if !(200...299).contains(status) {
            throw PayLinkError.server(errorMessage(in: data) ?? "The pay service rejected the request.")
        }
        do {
            return try JSONDecoder().decode(PayLinkSnapshot.self, from: data)
        } catch {
            throw PayLinkError.server("The pay service sent an unexpected response.")
        }
    }

    private func endpoint(_ path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        return components?.url ?? baseURL
    }

    private func errorMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let message = json["error"] as? String
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
