import Foundation
import SwiftData

/// Keeps one primary studio on the books and points ownerless invoices at it.
enum StudioBrandDirectory {
    @MainActor
    static func prepare(in context: ModelContext) throws {
        var studios = try context.fetch(FetchDescriptor<StudioBrand>())
        if studios.isEmpty {
            let studio = StudioBrand(name: StudioBrand.defaultName, isPrimary: true)
            context.insert(studio)
            studios = [studio]
        }
        ensureSinglePrimary(among: studios)
        guard let primary = studios.first(where: \.isPrimary) else { return }
        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        for invoice in invoices where invoice.studio == nil {
            invoice.studio = primary
        }
        try context.save()
    }

    @MainActor
    static func primary(in context: ModelContext) throws -> StudioBrand? {
        let studios = try context.fetch(FetchDescriptor<StudioBrand>())
        return studios.first { $0.isPrimary && !$0.archived } ?? studios.first { !$0.archived }
    }

    @MainActor
    static func makePrimary(_ studio: StudioBrand, in context: ModelContext) throws {
        let studios = try context.fetch(FetchDescriptor<StudioBrand>())
        for other in studios where other.persistentModelID != studio.persistentModelID {
            other.isPrimary = false
        }
        studio.isPrimary = true
        studio.archived = false
        try context.save()
    }

    /// Invoices move to the surviving primary. The last studio stays.
    @MainActor
    static func delete(_ studio: StudioBrand, in context: ModelContext) throws {
        let studios = try context.fetch(FetchDescriptor<StudioBrand>())
        let others = studios.filter { $0.persistentModelID != studio.persistentModelID }
        guard let destination = others.first(where: \.isPrimary) ?? others.first else { return }
        if studio.isPrimary {
            destination.isPrimary = true
            destination.archived = false
        }
        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        for invoice in invoices where invoice.studio?.persistentModelID == studio.persistentModelID {
            invoice.studio = destination
        }
        context.delete(studio)
        try context.save()
    }

    /// Archiving the primary promotes another active studio. The last active studio stays.
    @MainActor
    static func setArchived(_ studio: StudioBrand, archived: Bool, in context: ModelContext) throws {
        let studios = try context.fetch(FetchDescriptor<StudioBrand>())
        if archived, studio.isPrimary {
            guard let next = studios.first(where: {
                $0.persistentModelID != studio.persistentModelID && !$0.archived
            }) else { return }
            next.isPrimary = true
            studio.isPrimary = false
        }
        studio.archived = archived
        if !archived, !studios.contains(where: { $0.isPrimary && !$0.archived && $0.persistentModelID != studio.persistentModelID }) {
            for other in studios where other.persistentModelID != studio.persistentModelID {
                other.isPrimary = false
            }
            studio.isPrimary = true
        }
        try context.save()
    }

    static func canDelete(among studios: [StudioBrand]) -> Bool {
        studios.count > 1
    }

    static func canArchive(_ studio: StudioBrand, among studios: [StudioBrand]) -> Bool {
        guard studio.isPrimary else { return true }
        return studios.contains { $0.persistentModelID != studio.persistentModelID && !$0.archived }
    }

    private static func ensureSinglePrimary(among studios: [StudioBrand]) {
        let primaries = studios.filter(\.isPrimary)
        guard primaries.count != 1 || primaries.first?.archived == true else { return }
        for studio in studios {
            studio.isPrimary = false
        }
        let keeper = studios.first { !$0.archived } ?? studios[0]
        keeper.isPrimary = true
        keeper.archived = false
    }
}
