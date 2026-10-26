import SwiftUI
import SwiftData

@main
struct BigQApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try StudioStore.makeContainer()
        } catch {
            fatalError("Could not create the BigQ store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            StudioRootView()
        }
        .modelContainer(container)
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                NewInvoiceCommand()
                Button("Import ShootQ…") {
                    NotificationCenter.default.post(name: .bigShootImport, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Export Books…") {
                    NotificationCenter.default.post(name: .bigShootExport, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}
