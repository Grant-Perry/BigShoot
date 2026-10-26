import CryptoKit
import Foundation

enum BackupIdentity {
    /// Keeps an id already stored on the record. Assigns one the first time a backup sees it.
    static func stored(_ fileID: String) -> String {
        let trimmed = fileID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? UUID().uuidString : trimmed
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func digest(_ text: String) -> String {
        digest(Data(text.utf8))
    }
}
