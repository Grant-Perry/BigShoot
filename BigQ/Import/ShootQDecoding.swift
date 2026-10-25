import Foundation

struct ImportedLine: Sendable {
    var invoiceID: String
    var name: String
    var detail: String
    var quantity: Decimal
    var unitPrice: Decimal
    var packageName: String
}

enum ShootQMoney {
    static func decimal(_ string: String) -> Decimal {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// Rounds a JSON number to cents so money does not keep binary dust.
    static func cents(_ value: Double) -> Decimal {
        let scaled = (value * 100).rounded()
        return Decimal(Int(scaled)) / 100
    }
}

struct FlexDecimal: Decodable, Sendable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = 0
            return
        }
        if let string = try? container.decode(String.self) {
            value = ShootQMoney.decimal(string)
            return
        }
        if let int = try? container.decode(Int.self) {
            value = Decimal(int)
            return
        }
        if let double = try? container.decode(Double.self) {
            value = ShootQMoney.cents(double)
            return
        }
        value = 0
    }
}

struct FlexString: Decodable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = ""
            return
        }
        if let string = try? container.decode(String.self) {
            value = string
            return
        }
        if let int = try? container.decode(Int.self) {
            value = String(int)
            return
        }
        value = ""
    }
}

enum ShootQDates {
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "TBD" { return nil }
        if let date = isoFractional.date(from: text) { return date }
        if let date = iso.date(from: text) { return date }
        if let date = day.date(from: String(text.prefix(10))) { return date }
        if let date = spaceZone.date(from: text) { return date }
        return nil
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let spaceZone: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZZZZZ"
        return formatter
    }()
}

enum ShootQCSV {
    static func parse(_ text: String) -> [[String: String]] {
        let records = splitRecords(text)
        guard let header = records.first else { return [] }
        return records.dropFirst().compactMap { fields in
            if fields.allSatisfy({ $0.isEmpty }) { return nil }
            var row: [String: String] = [:]
            for (index, key) in header.enumerated() where index < fields.count {
                row[key] = fields[index]
            }
            return row
        }
    }

    private static func splitRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                field.append(character)
                index += 1
                continue
            }

            if character == "\"" {
                inQuotes = true
                index += 1
                continue
            }
            if character == "," {
                row.append(field)
                field = ""
                index += 1
                continue
            }
            if character == "\n" || character == "\r" {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                field = ""
                records.append(row)
                row = []
                index += 1
                continue
            }
            field.append(character)
            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            records.append(row)
        }
        return records
    }
}

// MARK: - Export records

struct ShootQContact: Decodable {
    let id: Int
    let firstName: String?
    let lastName: String?
    let fullName: String?
    let companyName: String?
    let archived: Bool?
    let created: String?
    let emails: [ShootQEmail]?
    let phones: [ShootQPhone]?
    let addresses: [ShootQAddress]?
    let dates: [ShootQDateStamp]?
    let defaultEmailDetails: ShootQEmail?
    let defaultPhoneDetails: ShootQPhone?
    let defaultAddressDetails: ShootQAddress?
}

struct ShootQEmail: Decodable {
    let address: String?
}

struct ShootQPhone: Decodable {
    let number: String?
}

struct ShootQAddress: Decodable {
    let fullAddress: String?
    let street: String?
    let city: String?
    let state: String?
    let zip: String?
}

struct ShootQDateStamp: Decodable {
    let dateType: String?
    let displayDate: String?
    let year: Int?
    let date: String?
}

struct ShootQJob: Decodable {
    let id: Int
    let name: String?
    let status: String?
    let mainEventDate: String?
    let jobTypeDetails: ShootQJobType?
    let externalOwner: ShootQOwner?
}

struct ShootQJobType: Decodable {
    let displayName: String?
    let name: String?
}

struct ShootQOwner: Decodable {
    let id: Int?
}

struct ShootQJobContact: Decodable {
    let job: Int
    let contact: Int
}

struct ShootQInvoice: Decodable {
    let id: Int
    let contact: Int?
    let job: Int?
    let discount: FlexDecimal?
    let balance: FlexDecimal?
    let billTo: ShootQBillTo?
    let shipping: FlexDecimal?
    let tax: FlexDecimal?
    let total: FlexDecimal?
    let paid: FlexDecimal?
    let status: String?
    let invoiceDate: String?
    let dueDate: String?
    let paidDate: String?
    let number: FlexString?
    let collectManually: Bool?
    let disableReminders: Bool?
    let message: String?
}

struct ShootQBillTo: Decodable {
    let fullName: String?
}

struct ShootQSchedule: Decodable {
    let id: Int
    let balance: FlexDecimal?
    let status: String?
    let amount: FlexDecimal?
    let paid: FlexDecimal?
    let due: String?
    let invoice: Int?
}

struct ShootQAppliedPayment: Decodable {
    let id: Int
    let amount: FlexDecimal?
    let created: String?
    let invoice: Int?
    let externalPayment: ShootQExternalPayment?
}

struct ShootQExternalPayment: Decodable {
    let paymentType: String?
    let datetime: String?
}

struct ShootQLineGroup: Decodable {
    let invoiceId: Int
    let items: [ShootQLinePayload]
}

struct ShootQLinePayload: Decodable {
    let package: String?
    let name: String?
    let detail: String?
    let quantity: FlexDecimal?
    let price: FlexDecimal?

    enum CodingKeys: String, CodingKey {
        case package, name, quantity, price
        case detail = "description"
    }
}

enum ShootQLineLoader {
    /// CSV wins when it is present and at least as complete as the jsonl scrape.
    /// A still-growing jsonl is used when it has more finished rows, and a torn last line is skipped.
    static func load(from folder: URL) -> (lines: [ImportedLine], skipped: Int, source: String) {
        var csvLines: [ImportedLine] = []
        let csvURL = folder.appendingPathComponent("invoice-line-items.csv")
        if FileManager.default.isReadableFile(atPath: csvURL.path),
           let text = try? String(contentsOf: csvURL, encoding: .utf8) {
            csvLines = linesFromCSV(text)
        }

        var jsonlLines: [ImportedLine] = []
        var skipped = 0
        let jsonlURL = folder.appendingPathComponent("invoice-line-items.jsonl")
        if FileManager.default.isReadableFile(atPath: jsonlURL.path) {
            let parsed = linesFromJSONL(jsonlURL)
            jsonlLines = parsed.lines
            skipped = parsed.skipped
        }

        if csvLines.isEmpty {
            return (jsonlLines, skipped, jsonlLines.isEmpty ? "none" : "invoice-line-items.jsonl")
        }
        if jsonlLines.count > csvLines.count {
            return (jsonlLines, skipped, "invoice-line-items.jsonl")
        }
        return (csvLines, 0, "invoice-line-items.csv")
    }

    private static func linesFromCSV(_ text: String) -> [ImportedLine] {
        ShootQCSV.parse(text).compactMap { row in
            let name = (row["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let invoiceID = row["invoice_id"], !invoiceID.isEmpty else { return nil }
            return ImportedLine(
                invoiceID: invoiceID,
                name: name,
                detail: row["description"] ?? "",
                quantity: ShootQMoney.decimal(row["quantity"] ?? "1"),
                unitPrice: ShootQMoney.decimal(row["price"] ?? "0"),
                packageName: row["package"] ?? ""
            )
        }
    }

    private static func linesFromJSONL(_ url: URL) -> (lines: [ImportedLine], skipped: Int) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return ([], 1)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var lines: [ImportedLine] = []
        var skipped = 0
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let payload = trimmed.data(using: .utf8),
                  let group = try? decoder.decode(ShootQLineGroup.self, from: payload) else {
                skipped += 1
                continue
            }
            for item in group.items {
                let name = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                lines.append(ImportedLine(
                    invoiceID: String(group.invoiceId),
                    name: name,
                    detail: item.detail ?? "",
                    quantity: item.quantity?.value ?? 1,
                    unitPrice: item.price?.value ?? 0,
                    packageName: item.package ?? ""
                ))
            }
        }
        return (lines, skipped)
    }
}
