import Foundation

/// How a backup folder is applied to this Mac.
enum BackupRestoreMode: String, CaseIterable, Identifiable, Sendable {
    case replace
    case merge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .replace: "Replace"
        case .merge: "Merge"
        }
    }

    var detail: String {
        switch self {
        case .replace: "Make this Mac match the backup. Records in that scope that exist only here are removed."
        case .merge: "Update matching records and add what is missing. Records that exist only here stay."
        }
    }

    var actionTitle: String {
        switch self {
        case .replace: "Replace"
        case .merge: "Merge"
        }
    }
}
