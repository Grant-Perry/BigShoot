import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Avatar control for a studio logo. Empty opens the file chooser; a logo opens edit, replace, and remove.
struct StudioLogoEditorButton: View {
    let title: String
    @Binding var imageData: Data?
    var sourceImageData: Binding<Data?>?
    var size: CGFloat = 96

    @State private var isShowingFileImporter = false
    @State private var isShowingPhotoActions = false
    @State private var pending: PendingStudioLogo?
    @State private var isPreparing = false

    var body: some View {
        Button(action: open) {
            avatar
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
        .accessibilityLabel("Add or change logo for \(title)")
        .popover(isPresented: $isShowingPhotoActions, arrowEdge: .bottom) {
            StudioLogoPhotoActions(
                onEdit: { runAfterPopover { Task { await presentExisting() } } },
                onChoose: { runAfterPopover { isShowingFileImporter = true } },
                onRemove: { runAfterPopover(clear) }
            )
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            // Start inside the handler. Access ends when the handler returns unless we claim it now.
            let canAccess = url.startAccessingSecurityScopedResource()
            Task {
                defer {
                    if canAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                await importImage(from: url)
            }
        }
        .sheet(item: $pending) { item in
            StudioLogoCropEditor(image: item.image) { data in
                commit(data, sourceData: item.sourceData)
            }
            .frame(width: 420, height: 520)
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            StudioLogoView(title: title, imageData: imageData, size: size)
            Image(systemName: imageData == nil ? "plus" : "photo")
                .font(.caption.weight(.bold))
                .foregroundStyle(StudioDesign.ink)
                .padding(size * 0.08)
                .background(StudioDesign.gold.gradient, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white, lineWidth: 1.5)
                }
                .offset(
                    x: StudioLogoMetrics.badgeOffset(for: size),
                    y: StudioLogoMetrics.badgeOffset(for: size)
                )
                .accessibilityHidden(true)
        }
        .overlay {
            if isPreparing {
                preparingOverlay
            }
        }
        .padding(StudioLogoMetrics.badgeDiameter(for: size) * 0.45)
        .contentShape(.rect)
        .clipped()
    }

    private var preparingOverlay: some View {
        RoundedRectangle(cornerRadius: StudioLogoMetrics.cornerRadius(for: size), style: .continuous)
            .fill(.black.opacity(0.45))
            .frame(width: size, height: size)
            .overlay {
                ProgressView()
                    .controlSize(.regular)
            }
    }

    private func open() {
        if imageData == nil {
            isShowingFileImporter = true
        } else {
            isShowingPhotoActions = true
        }
    }

    /// The popover has to leave before a file panel or crop sheet takes the window.
    private func runAfterPopover(_ action: @escaping () -> Void) {
        isShowingPhotoActions = false
        Task { @MainActor in
            action()
        }
    }

    private func clear() {
        sourceImageData?.wrappedValue = nil
        imageData = nil
    }

    private func commit(_ cropped: Data, sourceData: Data?) {
        if let sourceImageData, let sourceData {
            sourceImageData.wrappedValue = sourceData
        }
        imageData = cropped
    }

    @MainActor
    private func importImage(from url: URL) async {
        isPreparing = true
        defer { isPreparing = false }

        let raw = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
        guard let raw else { return }
        await stage(from: raw, sourceData: nil, boundSource: true)
    }

    @MainActor
    private func presentExisting() async {
        if let source = sourceImageData?.wrappedValue, !StudioLogoProcessor.exceedsSourceCap(source) {
            await stage(from: source, sourceData: source, boundSource: false)
        } else if let source = sourceImageData?.wrappedValue {
            await stage(from: source, sourceData: nil, boundSource: true)
        } else if let display = imageData {
            await stage(from: display, sourceData: nil, boundSource: false)
        }
    }

    /// `boundSource` shrinks a fresh pick. An existing original under the cap is passed through.
    @MainActor
    private func stage(from data: Data, sourceData: Data?, boundSource: Bool) async {
        isPreparing = true
        defer { isPreparing = false }

        let source: Data?
        if boundSource {
            let bounded = await Task.detached(priority: .userInitiated) {
                StudioLogoProcessor.boundedSourceJPEGData(from: data)
            }.value
            source = bounded ?? data
        } else {
            source = sourceData
        }
        let preview = source ?? data
        guard let cgImage = StudioLogoProcessor.cgImage(from: preview) else { return }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        pending = PendingStudioLogo(image: image, sourceData: source)
    }
}
