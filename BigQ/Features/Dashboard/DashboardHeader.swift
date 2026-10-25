import SwiftUI

struct DashboardHeader: View {
    var title: String
    var subtitle: String
    var showsPrimaryNote: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(StudioDesign.displayHero)
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
