import SwiftUI

/// Studio tokens borrowed from BigFli's Mac scale (spacing, radii, rounded metrics)
/// and BigRoll's charcoal night, with a warm gold accent instead of a sports blue.
enum StudioDesign {
    static let gold = Color(red: 0.80, green: 0.65, blue: 0.35)
    static let rose = Color(red: 0.86, green: 0.46, blue: 0.56)
    static let paid = Color(red: 0.38, green: 0.62, blue: 0.42)
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.13)

    /// Charcoal night, stepped. The room stays darkest, cards sit on it,
    /// and paper — the section you're editing — is the lightest dark.
    enum Surface {
        static let sceneLead = Color(red: 0.14, green: 0.15, blue: 0.20)
        static let scene = Color(red: 0.12, green: 0.13, blue: 0.17)
        static let sceneWarm = Color(red: 0.16, green: 0.14, blue: 0.12)
        static let card = Color(red: 0.17, green: 0.19, blue: 0.24)
        static let paper = Color(red: 0.23, green: 0.24, blue: 0.28)
    }

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

/// Pipeline stamp, such as Oct 26, '26 - 10:51 AM.
nonisolated enum StudioStamp {
    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date) % 100
        let month = formatted(date, format: "MMM", calendar: calendar)
        let time = formatted(date, format: "h:mm a", calendar: calendar)
            .replacingOccurrences(of: "\u{202F}", with: " ")
        return "\(month) \(day), '\(String(format: "%02d", year)) - \(time)"
    }

    private static func formatted(_ date: Date, format: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
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

    /// The card or sheet you are in. Heavier than the resting hairline, with a glow behind the stroke.
    func studioActive(
        _ active: Bool = true,
        color: Color = StudioDesign.gold,
        cornerRadius: CGFloat = StudioDesign.Radius.card
    ) -> some View {
        modifier(StudioActiveStrokeModifier(active: active, color: color, cornerRadius: cornerRadius))
    }
}

struct StudioSceneBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    StudioDesign.Surface.sceneLead,
                    StudioDesign.Surface.scene,
                    StudioDesign.Surface.sceneWarm,
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
                    ? StudioDesign.Surface.card.opacity(0.97)
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

private struct StudioActiveStrokeModifier: ViewModifier {
    var active: Bool
    var color: Color
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .overlay {
                if active {
                    shape
                        .stroke(color.opacity(colorScheme == .dark ? 0.55 : 0.38), lineWidth: 8)
                        .blur(radius: 6)
                    shape
                        .strokeBorder(color, lineWidth: 3)
                }
            }
            .shadow(color: active ? color.opacity(colorScheme == .dark ? 0.42 : 0.26) : .clear, radius: 14)
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
                    ? StudioDesign.Surface.paper
                    : Color(red: 0.99, green: 0.98, blue: 0.95))
            }
            .overlay {
                shape.strokeBorder(Color.primary.opacity(dark ? 0.14 : 0.08), lineWidth: 1)
            }
    }
}
