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
            StudioBrand.self,
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

enum StudioSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        StudioSchemaV2.models + [TaxSchedule.self]
    }
}

/// Same models as V3. The studio type has to sit on every version because invoices
/// reference it, so a V3→V4 stage would duplicate the checksum and crash staged migration.
/// The app still opens V4 directly, which lightweight-migrates older books.
enum StudioSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(4, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        StudioSchemaV3.models
    }
}

enum StudioMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [StudioSchemaV1.self, StudioSchemaV2.self, StudioSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: StudioSchemaV1.self,
        toVersion: StudioSchemaV2.self
    )

    /// Adds tax schedules, a taxable flag on catalog items and lines, and the rate snapped onto each invoice.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: StudioSchemaV2.self,
        toVersion: StudioSchemaV3.self
    )
}
