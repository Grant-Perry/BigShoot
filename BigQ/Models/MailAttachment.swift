import Foundation
import SwiftData

/// A file the studio added to a quote or invoice letter. The invoice or quote PDF is generated at send time and is not stored here.
@Model
final class MailAttachment {
    var fileName: String = ""
    var contentType: String = "application/octet-stream"
    @Attribute(.externalStorage) var bytes: Data = Data()
    var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    var quoteEmail: QuoteEmail?
    var invoiceEmail: InvoiceEmail?

    init(fileName: String, contentType: String, bytes: Data) {
        self.fileName = fileName
        self.contentType = contentType
        self.bytes = bytes
        self.createdAt = .now
    }
}
