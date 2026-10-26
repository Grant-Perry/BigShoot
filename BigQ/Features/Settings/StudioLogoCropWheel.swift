import AppKit
import SwiftUI

/// Scroll-wheel zoom for the logo crop, the same capture the profile crop uses.
struct StudioLogoCropWheel: NSViewRepresentable {
    let onZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> StudioLogoCropWheelView {
        let view = StudioLogoCropWheelView()
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: StudioLogoCropWheelView, context: Context) {
        nsView.onZoom = onZoom
    }
}

final class StudioLogoCropWheelView: NSView {
    var onZoom: ((CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        onZoom?(delta)
    }
}
