import Foundation

enum BackupCopy {
    static func confirmTitle(mode: BackupRestoreMode) -> String {
        switch mode {
        case .replace: "Replace with this backup?"
        case .merge: "Merge this backup?"
        }
    }

    static func confirmMessage(
        manifest: BackupManifest,
        local: BackupManifest.Counts,
        mode: BackupRestoreMode
    ) -> String {
        let scope = BackupScope(rawValue: manifest.scope) ?? .full
        let when = manifest.createdAt.formatted(date: .abbreviated, time: .shortened)
        let here = "This Mac has \(local.sentence(for: scope))."
        let there = "The \(scope.title.lowercased()) backup from \(when) has \(manifest.counts.sentence(for: scope))."
        let action: String
        switch mode {
        case .replace:
            action = "Replace removes those records on this Mac and loads the backup."
        case .merge:
            action = "Merge updates matching records, adds what is missing, and keeps records that exist only on this Mac."
        }
        if mode == .replace, let keeps = scope.replaceKeeps {
            return "\(here) \(there) \(action) \(keeps)"
        }
        return "\(here) \(there) \(action)"
    }

    static func finishedBackup(
        name: String,
        counts: BackupManifest.Counts,
        scope: BackupScope,
        bodiesSkipped: Int
    ) -> String {
        var text = "Saved \(name). \(counts.sentence(for: scope))."
        if bodiesSkipped > 0 {
            text += " Unchanged agreement files were left in place."
        }
        return text
    }

    static func finishedRestore(
        mode: BackupRestoreMode,
        scope: BackupScope,
        counts: BackupManifest.Counts
    ) -> String {
        let verb = mode == .replace ? "Replaced" : "Merged"
        return "\(verb) the \(scope.title.lowercased()). \(counts.sentence(for: scope))."
    }
}
