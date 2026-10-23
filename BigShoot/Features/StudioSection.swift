import SwiftUI

enum StudioSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case contacts
    case jobs
    case invoices
    case catalog
    case settings

    var id: String { rawValue }

    static var books: [StudioSection] {
        [.dashboard, .contacts, .jobs, .invoices, .catalog]
    }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .contacts: "Contacts"
        case .jobs: "Jobs"
        case .invoices: "Invoices"
        case .catalog: "Catalog"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .contacts: "person.2"
        case .jobs: "camera"
        case .invoices: "doc.text"
        case .catalog: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}

extension Notification.Name {
    static let bigShootNewInvoice = Notification.Name("BigShoot.NewInvoice")
    static let bigShootImport = Notification.Name("BigShoot.Import")
    static let bigShootExport = Notification.Name("BigShoot.Export")
}
