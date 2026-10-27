import SwiftUI

struct DashboardHeader: View {
    var title: String
    var subtitle: String
    var showsPrimaryNote: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if title.compare(StudioBanner.fallback, options: .caseInsensitive) == .orderedSame {
                BigQWordmark()
            } else {
                Text(title)
                    .font(StudioDesign.displayHero)
            }
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            if showsPrimaryNote {
                Text("Primary studio")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}
