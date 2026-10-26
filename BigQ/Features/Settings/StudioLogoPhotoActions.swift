import SwiftUI

/// Edit, replace, or remove — the same choices a profile photo offers once one is set.
struct StudioLogoPhotoActions: View {
    let onEdit: () -> Void
    let onChoose: () -> Void
    let onRemove: () -> Void

    @State private var hoveredTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row("Edit Logo", systemImage: "crop", action: onEdit)
            row("Choose from Computer", systemImage: "photo.on.rectangle", action: onChoose)
            Divider()
                .padding(.vertical, 3)
            row("Remove", systemImage: "trash", isDestructive: true, action: onRemove)
        }
        .padding(6)
        .frame(width: 210)
    }

    private func row(
        _ title: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(isDestructive ? Color.red : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hoveredTitle == title ? 0.10 : 0))
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredTitle = title
            } else if hoveredTitle == title {
                hoveredTitle = nil
            }
        }
    }
}
