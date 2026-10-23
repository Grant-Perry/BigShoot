import AppKit
import Darwin
import Foundation
import SwiftData

@MainActor
@Observable
final class ShootQImportModel {
    static let completedKey = "BigShoot.didCompleteImport"
    static let declinedKey = "BigShoot.didDeclineImport"
    static let bookmarkKey = "BigShoot.exportBookmark"

    var isPresentingOffer = false
    var isImporting = false
    var stepTitle = "Ready"
    var fraction = 0.0
    var errorMessage: String?
    var summary: ShootQImportSummary?
    var discoveredFolder: URL?

    var folderTitle: String {
        discoveredFolder?.path ?? "Choose the shootq-export folder"
    }

    func offerIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.completedKey),
              !UserDefaults.standard.bool(forKey: Self.declinedKey) else { return }
        discoveredFolder = Self.candidateFolder()
        isPresentingOffer = true
    }

    func presentForImport() {
        discoveredFolder = Self.resolveBookmark() ?? Self.candidateFolder()
        summary = nil
        errorMessage = nil
        isPresentingOffer = true
    }

    func decline() {
        UserDefaults.standard.set(true, forKey: Self.declinedKey)
        isPresentingOffer = false
    }

    func importPreferred(context: ModelContext) async {
        if let folder = discoveredFolder, Self.canRead(folder) {
            await run(folder, context: context)
            return
        }
        guard let picked = pickFolder() else { return }
        discoveredFolder = picked
        await run(picked, context: context)
    }

    func chooseAnother(context: ModelContext) async {
        guard let picked = pickFolder() else { return }
        discoveredFolder = picked
        await run(picked, context: context)
    }

    private func run(_ folder: URL, context: ModelContext) async {
        isImporting = true
        errorMessage = nil
        summary = nil
        fraction = 0
        defer { isImporting = false }
        do {
            let result = try await ShootQImporter(context: context) { title, fraction in
                self.stepTitle = title
                self.fraction = fraction
            }.run(folder: folder)
            summary = result
            UserDefaults.standard.set(true, forKey: Self.completedKey)
            Self.saveBookmark(folder)
            do {
                try StudioBrandDirectory.prepare(in: context)
            } catch {
                DebugPrint(mode: .error, "Could not attach imported invoices to a studio: \(error.localizedDescription)")
            }
        } catch {
            errorMessage = error.localizedDescription
            DebugPrint(mode: .error, "ShootQ import failed: \(error.localizedDescription)")
        }
    }

    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Import"
        panel.message = "Choose the shootq-export folder. Sent mail and contracts stay on disk."
        if let discoveredFolder {
            panel.directoryURL = discoveredFolder
        }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func candidateFolder() -> URL? {
        if let bookmark = resolveBookmark(), canRead(bookmark) { return bookmark }
        let folder = realHome.appendingPathComponent("Xcode/BigShoot/shootq-export", isDirectory: true)
        return canRead(folder) ? folder : nil
    }

    /// Sandboxed apps see a container as `homeDirectoryForCurrentUser`. The export sits in the real home.
    static var realHome: URL {
        if let passwd = getpwuid(getuid()), let directory = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func canRead(_ folder: URL) -> Bool {
        let marker = folder.appendingPathComponent("contacts-active.json")
        return FileManager.default.isReadableFile(atPath: marker.path)
    }

    static func saveBookmark(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}
