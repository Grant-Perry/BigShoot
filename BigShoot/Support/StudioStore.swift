import Foundation
import SwiftData

enum StudioStore {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StudioSchemaV2.self)
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = support.appendingPathComponent("BigShoot", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storeURL = folder.appendingPathComponent("BigShoot.store")
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(
            for: schema,
            migrationPlan: StudioMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
