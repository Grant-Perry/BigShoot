import SwiftUI

/// Studio tokens borrowed from BigFli's Mac scale (spacing, radii, rounded metrics)
/// and BigRoll's charcoal night, with a warm gold accent instead of a sports blue.
enum StudioDesign {
    static let gold = Color(red: 0.80, green: 0.65, blue: 0.35)
    static let rose = Color(red: 0.86, green: 0.46, blue: 0.56)
    static let paid = Color(red: 0.38, green: 0.62, blue: 0.42)
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.13)

    /// Calculated totals. `.gpMoney` on the night scene; the same mint pulled down so it reads on paper.
    static func money(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .gpMoney : Color(red: 0.11, green: 0.40, blue: 0.24)
    }

    enum Spacing {
        static let workspace: CGFloat = 28
        static let card: CGFloat = 18
        static let section: CGFloat = 20
        static let grid: CGFloat = 14
        static let tight: CGFloat = 8
    }

    enum Radius {
        static let card: CGFloat = 24
        static let tile: CGFloat = 20
        static let row: CGFloat = 14
    }

    static let displayHero: Font = .system(size: 40, weight: .regular, design: .default)
    static let displayTitle: Font = .system(size: 28, weight: .regular, design: .default)

    static func metric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

enum StudioMoney {
    static func string(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD"))
    }
}

nonisolated enum StudioDay {
    static func string(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

extension View {
    /// Large content pane. Gradient wash, not Liquid Glass and not a scroll material.
    func studioCard(cornerRadius: CGFloat = StudioDesign.Radius.card) -> some View {
        modifier(StudioCardModifier(cornerRadius: cornerRadius))
    }

    /// Invoice paper and other dense reading surfaces. Solid grouped fill.
    func paperCard(cornerRadius: CGFloat = StudioDesign.Radius.card) -> some View {
        modifier(PaperCardModifier(cornerRadius: cornerRadius))
    }
}

struct StudioSceneBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.10, green: 0.11, blue: 0.16),
                    StudioDesign.ink,
                    Color(red: 0.12, green: 0.10, blue: 0.09),
                ]
                : [
                    Color(red: 0.96, green: 0.95, blue: 0.92),
                    Color(red: 0.93, green: 0.90, blue: 0.86),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct StudioEmptyState: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatusBadge: View {
    var status: InvoiceStatus
    var title: String? = nil

    var body: some View {
        Text(title ?? status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch status {
        case .overdue: StudioDesign.rose
        case .paid: StudioDesign.paid
        case .pending: StudioDesign.gold
        case .draft, .void: .secondary
        }
    }
}

// MARK: - Content cards

private struct StudioCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = colorScheme == .dark
        content
            .background {
                shape.fill(dark
                    ? Color(red: 0.11, green: 0.13, blue: 0.18).opacity(0.94)
                    : Color(red: 0.99, green: 0.98, blue: 0.96).opacity(0.94))
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(dark ? 0.10 : 0.55),
                            Color.white.opacity(dark ? 0.02 : 0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(dark ? 0.32 : 0.85),
                            StudioDesign.gold.opacity(dark ? 0.18 : 0.28),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(dark ? 0.28 : 0.08), radius: 12, y: 6)
    }
}

private struct PaperCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = colorScheme == .dark
        content
            .background {
                shape.fill(dark
                    ? Color(red: 0.14, green: 0.14, blue: 0.16)
                    : Color(red: 0.99, green: 0.98, blue: 0.95))
            }
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}
