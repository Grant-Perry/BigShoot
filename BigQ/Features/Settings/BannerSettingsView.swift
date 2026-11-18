import SwiftUI

struct BannerSettingsView: View {
    @AppStorage(StudioBanner.key) private var bannerText = StudioBanner.fallback

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(StudioBanner.resolved(bannerText))
                        .font(StudioDesign.displayHero)
                    Text("Shown on the dashboard and in the sidebar.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                StudioLabeledStack {
                    StudioLabeledRow("Banner Text") {
                        TextField("Banner Text", text: $bannerText, prompt: Text(StudioBanner.fallback))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(StudioDesign.Spacing.card)
                .paperCard()

                Text("Leave this blank to use \(StudioBanner.fallback).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(StudioDesign.Spacing.workspace)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StudioSceneBackground())
    }
}
