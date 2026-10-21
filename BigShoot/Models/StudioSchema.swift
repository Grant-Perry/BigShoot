import SwiftData

enum StudioSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            Contact.self,
            Job.self,
            CatalogItem.self,
            Invoice.self,
            InvoiceLine.self,
            PaymentScheduleEntry.self,
            PaymentReceipt.self,
        ]
    }
}

enum StudioSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        StudioSchemaV1.models + [BooksEvent.self]
    }
}

enum StudioMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [StudioSchemaV1.self, StudioSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: StudioSchemaV1.self,
        toVersion: StudioSchemaV2.self
    )
}
