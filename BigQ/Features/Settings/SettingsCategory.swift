import Foundation

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case studios
    case agreements
    case banner
    case backup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studios: "Studios"
        case .agreements: "Agreements"
        case .banner: "Banner Text"
        case .backup: "Backup"
        }
    }

    var symbol: String {
        switch self {
        case .studios: "building.2"
        case .agreements: "signature"
        case .banner: "textformat"
        case .backup: "externaldrive"
        }
    }

    var subtitle: String {
        switch self {
        case .studios: "Name, address, and letterhead"
        case .agreements: "Reusable quote contracts"
        case .banner: "Dashboard and sidebar"
        case .backup: "Save and restore the studio"
        }
    }
}
