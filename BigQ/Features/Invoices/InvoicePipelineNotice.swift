import SwiftUI

/// Shown while editing an invoice that is already in the pipeline.
struct InvoicePipelineNotice: View {
    var submittedAt: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.gpWarning)
                .accessibilityHidden(true)
            Text("Submitted \(StudioStamp.string(submittedAt)). This invoice is already in the pipeline. Saving overwrites that submission.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioDesign.Surface.paper, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
