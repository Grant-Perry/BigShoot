import Foundation

enum BackupPackage {
    static let manifestName = "manifest.json"
    static let studioName = "studio.json"
    static let bodiesFolder = "bodies"
    static let mediaFolder = "media"

    static func suggestedName(for scope: BackupScope, on date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "BigQ-\(scope.fileToken)-\(formatter.string(from: date)).bigqbackup"
    }

    /// Writes the books every time. An agreement file that is already in the folder stays untouched.
    static func write(_ payload: BackupPayload, to url: URL) throws -> BackupWriteResult {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path), !url.hasDirectoryPath, !isDirectory(url) {
            throw BackupError.unreadable
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        let bodies = url.appendingPathComponent(bodiesFolder, isDirectory: true)
        let media = url.appendingPathComponent(mediaFolder, isDirectory: true)
        try fileManager.createDirectory(at: bodies, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: media, withIntermediateDirectories: true)

        var written = 0
        var skipped = 0
        for (hash, data) in payload.bodies {
            let destination = bodies.appendingPathComponent("\(hash).html")
            if fileManager.fileExists(atPath: destination.path) {
                skipped += 1
                continue
            }
            try data.write(to: destination, options: .atomic)
            written += 1
        }
        for (hash, data) in payload.media {
            let destination = media.appendingPathComponent(hash)
            if fileManager.fileExists(atPath: destination.path) { continue }
            try data.write(to: destination, options: .atomic)
        }

        let encoder = BackupCoding.encoder()
        try encoder.encode(payload.file).write(to: url.appendingPathComponent(studioName), options: .atomic)
        let manifest = BackupManifest(
            format: payload.file.format,
            scope: payload.file.scope,
            createdAt: payload.file.createdAt,
            counts: payload.file.counts
        )
        try encoder.encode(manifest).write(to: url.appendingPathComponent(manifestName), options: .atomic)
        return BackupWriteResult(counts: payload.file.counts, bodiesWritten: written, bodiesSkipped: skipped)
    }

    static func manifest(at url: URL) throws -> BackupManifest {
        let data = try Data(contentsOf: try root(of: url).appendingPathComponent(manifestName))
        let manifest = try decode(BackupManifest.self, from: data)
        try validate(format: manifest.format, scope: manifest.scope)
        return manifest
    }

    static func load(at url: URL) throws -> BackupPayload {
        let root = try root(of: url)
        let file = try decode(BackupFile.self, from: Data(contentsOf: root.appendingPathComponent(studioName)))
        try validate(format: file.format, scope: file.scope)
        let fileManager = FileManager.default
        var bodies: [String: Data] = [:]
        for contract in file.contracts {
            guard let hash = contract.bodyFile, bodies[hash] == nil else { continue }
            let body = root.appendingPathComponent(bodiesFolder).appendingPathComponent("\(hash).html")
            guard fileManager.fileExists(atPath: body.path) else { continue }
            bodies[hash] = try Data(contentsOf: body)
        }
        var media: [String: Data] = [:]
        for studio in file.studios {
            for hash in [studio.logoFile, studio.logoSourceFile].compactMap({ $0 }) where media[hash] == nil {
                let image = root.appendingPathComponent(mediaFolder).appendingPathComponent(hash)
                guard fileManager.fileExists(atPath: image.path) else { continue }
                media[hash] = try Data(contentsOf: image)
            }
        }
        return BackupPayload(file: file, bodies: bodies, media: media)
    }

    private static func root(of url: URL) throws -> URL {
        let manifest = url.appendingPathComponent(manifestName)
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw BackupError.notABackup
        }
        return url
    }

    private static func validate(format: Int, scope: String) throws {
        guard format == BackupCoding.format else { throw BackupError.unsupportedFormat }
        guard BackupScope(rawValue: scope) != nil else { throw BackupError.unsupportedFormat }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try BackupCoding.decoder().decode(type, from: data)
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.unreadable
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }
}
