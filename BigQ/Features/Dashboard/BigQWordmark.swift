import SwiftUI

/// "Big" in the display face, set tight against the gold Q cut from the app icon.
struct BigQWordmark: View {
    /// Bowl bottom as a fraction of the asset. The tail hangs past this line.
    private static let bowlBaseline: CGFloat = 826.0 / 876.0
    /// A step above the cap height of `StudioDesign.displayHero` (40pt regular).
    private static let height: CGFloat = 42
    private static let aspect: CGFloat = 810.0 / 876.0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: -5) {
            Text("Big")
                .font(StudioDesign.displayHero)
                .zIndex(1)
            Image("WordmarkQ")
                .resizable()
                .interpolation(.high)
                .frame(width: Self.height * Self.aspect, height: Self.height)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions.height * Self.bowlBaseline
                }
                .offset(x: -5)
                .zIndex(0)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BigQ")
    }
}
