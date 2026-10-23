import Foundation

/// Version and copyright lines shared by the window footer.
nonisolated enum AppConstants {
    static var appMarketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    static var appBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    static var appVersionLine: String {
        "Version \(appMarketingVersion) (\(appBuildNumber))"
    }

    static var copyrightLine: String {
        let year = Calendar.current.component(.year, from: .now)
        return "Copyright © \(year) Cre8vPlanet Studios, LLC. - All rights reserved."
    }
}
