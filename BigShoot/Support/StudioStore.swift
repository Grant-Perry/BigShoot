import Foundation
import SwiftData

enum StudioStore {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StudioSchemaV4.self)
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = support.appendingPathComponent("BigShoot", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storeURL = folder.appendingPathComponent("BigShoot.store")
        backupOnce(storeURL, markerName: "BigShoot.store.pre-tax-backup")
        backupOnce(storeURL, markerName: "BigShoot.store.pre-studio-backup")
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        // Older books don't match the staged version stamps. Opening the latest schema
        // lightweight-migrates new columns and the studio model.
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// One copy of the books, taken the first time this marker is missing.
    private static func backupOnce(_ storeURL: URL, markerName: String) {
        let folder = storeURL.deletingLastPathComponent()
        let marker = folder.appendingPathComponent(markerName)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path),
              !fileManager.fileExists(atPath: marker.path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: marker.path + suffix)
            try? fileManager.copyItem(at: source, to: destination)
        }
    }
}
