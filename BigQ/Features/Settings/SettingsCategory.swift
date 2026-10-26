import Foundation

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case studios
    case banner
    case backup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studios: "Studios"
        case .banner: "Banner Text"
        case .backup: "Backup"
        }
    }

    var symbol: String {
        switch self {
        case .studios: "building.2"
        case .banner: "textformat"
        case .backup: "externaldrive"
        }
    }

    var subtitle: String {
        switch self {
        case .studios: "Name, address, and letterhead"
        case .banner: "Dashboard and sidebar"
        case .backup: "Save and restore the studio"
        }
    }
}
