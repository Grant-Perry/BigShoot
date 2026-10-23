import Foundation

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case studios
    case banner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studios: "Studios"
        case .banner: "Banner Text"
        }
    }

    var symbol: String {
        switch self {
        case .studios: "building.2"
        case .banner: "textformat"
        }
    }

    var subtitle: String {
        switch self {
        case .studios: "Name, address, and letterhead"
        case .banner: "Dashboard and sidebar"
        }
    }
}
