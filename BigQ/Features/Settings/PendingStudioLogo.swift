import AppKit

struct PendingStudioLogo: Identifiable {
    let id = UUID()
    let image: NSImage
    /// Original bytes kept so the crop can be redone. Nil when only the current crop is on hand.
    let sourceData: Data?
}
