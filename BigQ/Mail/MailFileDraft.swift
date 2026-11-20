import Foundation
import SwiftData
import UniformTypeIdentifiers

/// A file sitting in the letter editor, before or after it is saved on the email.
struct MailFileDraft: Identifiable {
    let id: UUID
    var fileName: String
    var contentType: String
    var bytes: Data
    var storedID: PersistentIdentifier?

    init(fileName: String, contentType: String, bytes: Data, storedID: PersistentIdentifier? = nil) {
        self.id = UUID()
        self.fileName = fileName
        self.contentType = contentType
        self.bytes = bytes
        self.storedID = storedID
    }

    init(_ attachment: MailAttachment) {
        self.init(
            fileName: attachment.fileName,
            contentType: attachment.contentType,
            bytes: attachment.bytes,
            storedID: attachment.persistentModelID
        )
    }
}

enum MailFileLimits {
    static let maxFiles = 6
    static let maxFileBytes = 8_000_000
    static let maxTotalBytes = 8_000_000
    static let note = "Add a PDF or any other file. Up to 6 files, 8 MB altogether."
}

enum MailFileName {
    private static let blocked: Set<String> = [
        "exe", "dmg", "app", "sh", "command", "js", "jar", "bat", "cmd", "msi", "pkg", "html", "htm", "svg",
    ]

    /// A name Postmark will accept. Empty when this type should not be mailed.
    static func safe(_ original: String) -> String? {
        let base = (original as NSString).lastPathComponent
        let ext = (base as NSString).pathExtension
        let stem = (base as NSString).deletingPathExtension
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".&' _()-"))
        let cleanedStem = String(stem.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        let cleanedExt = String(ext.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }).lowercased()
        let safeExt = String((cleanedExt.isEmpty ? "bin" : cleanedExt).prefix(8))
        guard !blocked.contains(safeExt) else { return nil }
        var safeStem = cleanedStem.isEmpty ? "File" : String(cleanedStem.prefix(80))
        if let first = safeStem.first, !first.isLetter, !first.isNumber {
            safeStem = "File-\(safeStem)"
        }
        return "\(safeStem).\(safeExt)"
    }

    static func contentType(for url: URL) -> String {
        guard let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType else {
            return "application/octet-stream"
        }
        let lower = mime.lowercased()
        if lower.count > 80 || lower.contains("javascript") || lower.contains("html") || lower == "image/svg+xml" {
            return "application/octet-stream"
        }
        return lower
    }
}

struct StagedMailFile {
    var url: URL
    var contentType: String
}

enum MailFileStaging {
    static func write(_ drafts: [MailFileDraft], to directory: URL) -> [StagedMailFile]? {
        var used = Set<String>()
        var staged: [StagedMailFile] = []
        for draft in drafts {
            guard var name = MailFileName.safe(draft.fileName) else { return nil }
            let stem = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var bump = 2
            while used.contains(name)
                || FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
                name = "\(stem)-\(bump).\(ext)"
                bump += 1
            }
            used.insert(name)
            let url = directory.appendingPathComponent(name)
            do {
                try draft.bytes.write(to: url, options: .atomic)
            } catch {
                DebugPrint(mode: .error, "Could not write attachment \(name): \(error.localizedDescription)")
                return nil
            }
            staged.append(StagedMailFile(url: url, contentType: draft.contentType))
        }
        return staged
    }
}

struct MailFileImportResult {
    var files: [MailFileDraft]
    var message: String?
}

enum MailFileImport {
    static func load(urls: [URL], existing: [MailFileDraft]) -> MailFileImportResult {
        var files: [MailFileDraft] = []
        var message: String?
        var count = existing.count
        var total = existing.reduce(0) { $0 + $1.bytes.count }
        for url in urls {
            if let file = take(url, count: &count, total: &total, message: &message) {
                files.append(file)
            }
        }
        return MailFileImportResult(files: files, message: message)
    }

    static func validated(
        name: String,
        contentType: String,
        bytes: Data,
        existingCount: Int,
        existingBytes: Int
    ) -> MailFileDraft? {
        guard existingCount < MailFileLimits.maxFiles else { return nil }
        guard !bytes.isEmpty, bytes.count <= MailFileLimits.maxFileBytes else { return nil }
        guard existingBytes + bytes.count <= MailFileLimits.maxTotalBytes else { return nil }
        guard let safe = MailFileName.safe(name) else { return nil }
        return MailFileDraft(fileName: safe, contentType: contentType, bytes: bytes)
    }

    private static func take(
        _ url: URL,
        count: inout Int,
        total: inout Int,
        message: inout String?
    ) -> MailFileDraft? {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            message = message ?? "Folders can’t be attached."
            return nil
        }
        if count >= MailFileLimits.maxFiles {
            message = message ?? "You can add up to \(MailFileLimits.maxFiles) files."
            return nil
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: url)
        } catch {
            message = message ?? "Couldn’t read \(url.lastPathComponent)."
            return nil
        }
        if bytes.isEmpty {
            message = message ?? "\(url.lastPathComponent) is empty."
            return nil
        }
        if bytes.count > MailFileLimits.maxFileBytes || total + bytes.count > MailFileLimits.maxTotalBytes {
            message = message ?? "Added files stay under 8 MB altogether."
            return nil
        }
        guard let safe = MailFileName.safe(url.lastPathComponent) else {
            message = message ?? "\(url.lastPathComponent) can’t be attached."
            return nil
        }
        count += 1
        total += bytes.count
        return MailFileDraft(fileName: safe, contentType: MailFileName.contentType(for: url), bytes: bytes)
    }
}

@MainActor
enum MailAttachmentSync {
    static func apply(
        _ drafts: [MailFileDraft],
        quote: QuoteEmail?,
        invoice: InvoiceEmail?,
        in context: ModelContext
    ) {
        let current = quote?.files ?? invoice?.files ?? []
        let kept = Set(drafts.compactMap(\.storedID))
        for file in current where !kept.contains(file.persistentModelID) {
            context.delete(file)
        }
        for draft in drafts where draft.storedID == nil {
            let file = MailAttachment(fileName: draft.fileName, contentType: draft.contentType, bytes: draft.bytes)
            file.quoteEmail = quote
            file.invoiceEmail = invoice
            context.insert(file)
        }
    }
}
