import Foundation
import os

// MARK: - Debug configuration

enum DebugConfig {
    nonisolated(unsafe) static var activeMode: DebugMode = []

    /// Launch argument `-BigShootDebugModes import,error`. Absent means nothing prints.
    static let launchArgumentKey = "BigShootDebugModes"

    static func configureFromLaunchArguments(defaults: UserDefaults = .standard) {
        guard let raw = defaults.string(forKey: launchArgumentKey) else { return }
        activeMode.formUnion(DebugMode.parse(raw))
    }
}

nonisolated struct DebugMode: OptionSet, Sendable {
    let rawValue: Int

    nonisolated static let info = DebugMode(rawValue: 1 << 0)
    nonisolated static let error = DebugMode(rawValue: 1 << 1)
    nonisolated static let `import` = DebugMode(rawValue: 1 << 2)

    nonisolated static let all: DebugMode = [.info, .error, .import]

    private nonisolated static let namedModes: [String: DebugMode] = [
        "info": .info,
        "error": .error,
        "import": .import,
        "all": .all,
    ]

    nonisolated static func parse(_ list: String) -> DebugMode {
        list.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .compactMap { namedModes[$0] }
            .reduce(into: DebugMode()) { $0.formUnion($1) }
    }
}

private nonisolated let debugLogger = Logger(
    subsystem: "com.grantperry.BigShoot",
    category: "DebugPrint"
)

nonisolated func DebugPrint(
    mode: DebugMode = .info,
    _ message: @autoclosure () -> String,
    file: String = #file,
    line: Int = #line,
    function: String = #function
) {
    guard DebugConfig.activeMode.contains(mode) else { return }
    let fileName = (file as NSString).lastPathComponent
    let actualMessage = message()
    debugLogger.debug("[\(fileName, privacy: .public):\(line)] \(function, privacy: .public) - \(actualMessage, privacy: .public)")
}
