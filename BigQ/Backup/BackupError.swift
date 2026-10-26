import Foundation

enum BackupError: Error, LocalizedError {
    case notABackup
    case unsupportedFormat
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notABackup:
            "That folder is not a BigQ backup."
        case .unsupportedFormat:
            "This backup was written by a newer BigQ and cannot be read."
        case .unreadable:
            "That backup could not be read."
        }
    }
}
