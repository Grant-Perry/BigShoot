import AppKit
import Foundation
import SwiftData

@MainActor
@Observable
final class BackupSettingsModel {
    var scope: BackupScope = .full
    var restoreMode: BackupRestoreMode = .replace
    var status: String?
    var statusIsError = false
    var isBusy = false
    var isConfirming = false
    var confirmTitle = ""
    var confirmMessage = ""

    private var pendingURL: URL?
    private var pendingAccess = false

    func backup(in context: ModelContext) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Back Up"
        panel.nameFieldStringValue = BackupPackage.suggestedName(for: scope)
        panel.message = "Save a BigQ backup. Choosing an existing backup folder refreshes the books and leaves unchanged agreement files in place."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try BackupExport.write(context: context, scope: scope, defaults: .standard, to: url)
            status = BackupCopy.finishedBackup(
                name: url.lastPathComponent,
                counts: result.counts,
                scope: scope,
                bodiesSkipped: result.bodiesSkipped
            )
            statusIsError = false
        } catch {
            fail(error)
        }
    }

    func chooseRestore(in context: ModelContext) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Restore"
        panel.message = "Choose a BigQ backup folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cancelRestore()
        pendingAccess = url.startAccessingSecurityScopedResource()
        pendingURL = url
        do {
            let manifest = try BackupPackage.manifest(at: url)
            let local = try BackupExport.counts(in: context)
            confirmTitle = BackupCopy.confirmTitle(mode: restoreMode)
            confirmMessage = BackupCopy.confirmMessage(manifest: manifest, local: local, mode: restoreMode)
            isConfirming = true
        } catch {
            cancelRestore()
            fail(error)
        }
    }

    func performRestore(in context: ModelContext) {
        guard let url = pendingURL else { return }
        isBusy = true
        defer {
            isBusy = false
            cancelRestore()
        }
        do {
            let payload = try BackupPackage.load(at: url)
            let counts = try BackupRestore.apply(payload, mode: restoreMode, context: context, defaults: .standard)
            let restoredScope = BackupScope(rawValue: payload.file.scope) ?? scope
            status = BackupCopy.finishedRestore(mode: restoreMode, scope: restoredScope, counts: counts)
            statusIsError = false
        } catch {
            fail(error)
        }
    }

    func cancelRestore() {
        if pendingAccess, let pendingURL {
            pendingURL.stopAccessingSecurityScopedResource()
        }
        pendingURL = nil
        pendingAccess = false
    }

    private func fail(_ error: Error) {
        DebugPrint(mode: .error, "Backup failed: \(error.localizedDescription)")
        status = error.localizedDescription
        statusIsError = true
    }
}
