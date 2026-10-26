import CoreGraphics

enum StudioLogoMetrics {
    static let cornerRadiusRatio: CGFloat = 0.22

    static func badgeDiameter(for size: CGFloat) -> CGFloat {
        size * 0.26
    }

    static func badgeOffset(for size: CGFloat) -> CGFloat {
        size * 0.05
    }

    static func cornerRadius(for size: CGFloat) -> CGFloat {
        size * cornerRadiusRatio
    }
}
