import SwiftData
import SwiftUI

/// Studio name on the leading edge, logo avatar on the top trailing corner.
struct StudioBrandIdentityHeader: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var studio: StudioBrand
    var roleLine: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(studio.displayName)
                .font(StudioDesign.displayHero)
            if studio.isPrimary {
                Text("Primary studio")
                    .font(.title3)
                    .foregroundStyle(StudioDesign.gold)
            }
            Text(roleLine)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .padding(.trailing, 140)
        .overlay(alignment: .topTrailing) {
            StudioLogoEditorButton(
                title: studio.displayName,
                imageData: $studio.logoImageData,
                sourceImageData: $studio.logoImageSourceData
            )
            .id(studio.persistentModelID)
        }
        .onChange(of: studio.logoImageData) { _, _ in
            persist()
        }
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            DebugPrint(mode: .error, "Could not save the studio logo: \(error.localizedDescription)")
        }
    }
}
