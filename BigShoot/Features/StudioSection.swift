import SwiftUI

enum StudioSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case contacts
    case jobs
    case invoices
    case catalog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .contacts: "Contacts"
        case .jobs: "Jobs"
        case .invoices: "Invoices"
        case .catalog: "Catalog"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .contacts: "person.2"
        case .jobs: "camera"
        case .invoices: "doc.text"
        case .catalog: "list.bullet.rectangle"
        }
    }
}

extension Notification.Name {
    static let bigShootNewInvoice = Notification.Name("BigShoot.NewInvoice")
    static let bigShootImport = Notification.Name("BigShoot.Import")
    static let bigShootExport = Notification.Name("BigShoot.Export")
}
