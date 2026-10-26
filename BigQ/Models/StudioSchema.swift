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
/// The app still opens the latest schema directly, which lightweight-migrates older books.
enum StudioSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(4, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        StudioSchemaV3.models
    }
}

/// Adds the invoice closing. Opened directly, same as V4, so the new column migrates in place.
enum StudioSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(5, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        StudioSchemaV4.models
    }
}

/// Adds the submitted stamp. Opened directly, same as V5, so the new column migrates in place.
enum StudioSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(6, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        StudioSchemaV5.models
    }
}

/// Adds ShootQ contracts and the signature rows that tie them to a client.
enum StudioSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(7, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        StudioSchemaV6.models + [Contract.self, ContractSignature.self]
    }
}

/// Adds the studio logo. Opened directly, same as V7, so the new columns migrate in place.
enum StudioSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(8, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        StudioSchemaV7.models
    }
}

/// Adds a stable archive id so a backup can match records on another Mac.
/// Opened directly, same as V8, so the new column migrates in place.
enum StudioSchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(9, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        StudioSchemaV8.models
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
