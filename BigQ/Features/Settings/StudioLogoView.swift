import AppKit
import SwiftUI

/// Studio mark. A chosen logo fills the rounded square; otherwise the building mark shows.
struct StudioLogoView: View {
    let title: String
    let imageData: Data?
    var size: CGFloat = 96

    private var cornerRadius: CGFloat {
        StudioLogoMetrics.cornerRadius(for: size)
    }

    var body: some View {
        Group {
            if let imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(StudioDesign.gold.opacity(0.18))
                    Image(systemName: "building.2.fill")
                        .font(.system(size: size * 0.34, weight: .semibold))
                        .foregroundStyle(StudioDesign.gold)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.85), lineWidth: max(1.5, size * 0.025))
        }
        .accessibilityLabel(title)
    }
}
