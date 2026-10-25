import SwiftUI

/// Version + copyright whisper, matching BigFli's `MacAppFooterView` /
/// `MacWorkspaceFooterBar`. Laid out under the split view as a sibling so
/// the bar keeps its own height and workspace scroll views end above it.
struct StudioAppFooterView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            Text(AppConstants.appVersionLine)
            Text(AppConstants.copyrightLine)
        }
        .font(.caption)
        .multilineTextAlignment(.center)
        .foregroundStyle(footerInk)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, StudioDesign.Spacing.workspace)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background {
            Rectangle()
                .fill(colorScheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.bar))
                .overlay(alignment: .top) {
                    Divider().opacity(colorScheme == .dark ? 0.35 : 0.22)
                }
        }
        .accessibilityElement(children: .combine)
    }

    private var footerInk: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.42)
            : Color(red: 0.10, green: 0.12, blue: 0.17).opacity(0.46)
    }
}

#Preview {
    StudioAppFooterView()
        .frame(width: 880)
        .padding(.top, 40)
        .background(StudioSceneBackground())
}
