import Darwin
import Foundation
import SwiftData

enum StudioStore {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StudioSchemaV9.self)
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = support.appendingPathComponent("BigQ", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storeURL = folder.appendingPathComponent("BigQ.store")
        try adoptLegacyBooksIfNeeded(folder: folder, storeURL: storeURL)
        backupOnce(storeURL, markerName: "BigQ.store.pre-tax-backup")
        backupOnce(storeURL, markerName: "BigQ.store.pre-studio-backup")
        backupOnce(storeURL, markerName: "BigQ.store.pre-closing-backup")
        backupOnce(storeURL, markerName: "BigQ.store.pre-submitted-backup")
        backupOnce(storeURL, markerName: "BigQ.store.pre-contract-backup")
        backupOnce(storeURL, markerName: "BigQ.store.pre-logo-backup")
        backupOnce(storeURL, markerName: "BigQ.store.pre-archive-backup")
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

    // MARK: - Legacy BigShoot container

    /// The previous bundle id still owns the books. Copy them once, before this container opens an empty store.
    private static func adoptLegacyBooksIfNeeded(folder: URL, storeURL: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: storeURL.path) else { return }
        if try adoptHandoff(folder: folder) { return }
        let legacyFolder = legacySupportFolder
        let legacyStore = legacyFolder.appendingPathComponent("BigShoot.store")
        guard fileManager.fileExists(atPath: legacyStore.path) else { return }
        for name in legacyFileNames {
            let source = legacyFolder.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = folder.appendingPathComponent(name.replacingOccurrences(of: "BigShoot", with: "BigQ"))
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            do {
                try copyLegacyFile(from: source, to: destination)
            } catch {
                return
            }
        }
        adoptLegacyPreferences()
    }

    /// Books carried inside this build. The sandbox can read its own bundle, not the old container.
    private static func adoptBundledHandoff(folder: URL) throws -> Bool {
        guard let root = Bundle.main.resourceURL else { return false }
        let store = root.appendingPathComponent("BigQ.store")
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: store.path) else { return false }
        for name in handoffFileNames {
            let source = root.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = folder.appendingPathComponent(name)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try copyLegacyFile(from: source, to: destination)
        }
        adoptHandoffPreferences(root.appendingPathComponent("preferences.plist"))
        return fileManager.fileExists(atPath: folder.appendingPathComponent("BigQ.store").path)
    }

    /// Books exported by the previous app into the project folder. That path is readable; the old container is not.
    private static func adoptHandoff(folder: URL) throws -> Bool {
        if try adoptBundledHandoff(folder: folder) { return true }
        let handoff = realHome.appendingPathComponent("Xcode/BigQ/handoff", isDirectory: true)
        let store = handoff.appendingPathComponent("BigQ.store")
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: store.path) else { return false }
        for name in handoffFileNames {
            let source = handoff.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = folder.appendingPathComponent(name)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try copyLegacyFile(from: source, to: destination)
        }
        adoptHandoffPreferences(handoff.appendingPathComponent("preferences.plist"))
        return fileManager.fileExists(atPath: folder.appendingPathComponent("BigQ.store").path)
    }

    private static func adoptHandoffPreferences(_ plist: URL) {
        guard let data = try? Data(contentsOf: plist),
              let stored = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        let defaults = UserDefaults.standard
        for (key, value) in stored where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    /// `copyItem` is denied across the old container. Reading and writing the bytes is allowed.
    private static func copyLegacyFile(from source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        try data.write(to: destination, options: .atomic)
    }

    private static func adoptLegacyPreferences() {
        let plist = realHome.appendingPathComponent(
            "Library/Containers/com.grantperry.BigShoot/Data/Library/Preferences/com.grantperry.BigShoot.plist"
        )
        guard let data = try? Data(contentsOf: plist),
              let stored = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        let defaults = UserDefaults.standard
        for (legacyKey, key) in legacyPreferenceKeys {
            guard defaults.object(forKey: key) == nil, let value = stored[legacyKey] else { continue }
            if key == StudioBanner.key, let banner = value as? String, (banner == "BigShoot" || banner == "BigSnoot") {
                defaults.set(StudioBanner.fallback, forKey: key)
            } else {
                defaults.set(value, forKey: key)
            }
        }
    }

    private static var legacySupportFolder: URL {
        realHome.appendingPathComponent(
            "Library/Containers/com.grantperry.BigShoot/Data/Library/Application Support/BigShoot",
            isDirectory: true
        )
    }

    /// Sandbox home is the new container. The old books sit under the real home.
    private static var realHome: URL {
        if let passwd = getpwuid(getuid()), let directory = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static let handoffFileNames = [
        "BigQ.store",
        "BigQ.store-wal",
        "BigQ.store-shm",
        "BigQ.store.pre-tax-backup",
        "BigQ.store.pre-tax-backup-wal",
        "BigQ.store.pre-tax-backup-shm",
        "BigQ.store.pre-studio-backup",
        "BigQ.store.pre-studio-backup-wal",
        "BigQ.store.pre-studio-backup-shm",
        "BigQ.store.pre-closing-backup",
        "BigQ.store.pre-closing-backup-wal",
        "BigQ.store.pre-closing-backup-shm",
        "BigQ.store.pre-submitted-backup",
        "BigQ.store.pre-submitted-backup-wal",
        "BigQ.store.pre-submitted-backup-shm",
    ]

    private static let legacyFileNames = [
        "BigShoot.store",
        "BigShoot.store-wal",
        "BigShoot.store-shm",
        "BigShoot.store.pre-tax-backup",
        "BigShoot.store.pre-tax-backup-wal",
        "BigShoot.store.pre-tax-backup-shm",
        "BigShoot.store.pre-studio-backup",
        "BigShoot.store.pre-studio-backup-wal",
        "BigShoot.store.pre-studio-backup-shm",
        "BigShoot.store.pre-closing-backup",
        "BigShoot.store.pre-closing-backup-wal",
        "BigShoot.store.pre-closing-backup-shm",
    ]

    private static let legacyPreferenceKeys = [
        "BigShoot.bannerText": "BigQ.bannerText",
        "BigShoot.didCompleteImport": "BigQ.didCompleteImport",
        "BigShoot.didDeclineImport": "BigQ.didDeclineImport",
        "BigShoot.exportBookmark": "BigQ.exportBookmark",
        "BigShoot.paymentMethods": "BigQ.paymentMethods",
        "BigShoot.jobTypes": "BigQ.jobTypes",
    ]
}
