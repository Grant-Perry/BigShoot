import AppKit
import SwiftUI

/// Drag, scroll, and zoom, then keep the square that becomes the studio logo.
struct StudioLogoCropEditor: View {
    @Environment(\.dismiss) private var dismiss

    let image: NSImage
    let onSave: (Data) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let cropSide: CGFloat = 280
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4

    private var cropCornerRadius: CGFloat {
        StudioLogoMetrics.cornerRadius(for: cropSide)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Drag to move the image. Scroll, pinch, or use the slider to zoom.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                ZStack {
                    Color.black.opacity(0.85)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(dragGesture)
                        .gesture(magnifyGesture)
                }
                .frame(width: cropSide, height: cropSide)
                .clipShape(RoundedRectangle(cornerRadius: cropCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cropCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                }
                .background {
                    StudioLogoCropWheel { delta in
                        applyScrollWheelZoom(delta)
                    }
                }

                zoomControls
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .background(StudioSceneBackground())
            .navigationTitle("Adjust Logo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Logo", action: useLogo)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var zoomControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Zoom out")

                Slider(
                    value: Binding(
                        get: { scale },
                        set: { newValue in
                            scale = clampedScale(newValue)
                            lastScale = scale
                        }
                    ),
                    in: minScale...maxScale
                )
                .accessibilityLabel("Zoom")

                Button(action: zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Zoom in")
            }

            Button("Reset position and zoom", action: resetCropTransform)
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = clampedScale(lastScale * value.magnification)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private func cancel() {
        dismiss()
    }

    private func useLogo() {
        if let data = StudioLogoProcessor.croppedJPEGData(
            from: image,
            offset: offset,
            scale: scale,
            cropSide: cropSide
        ) {
            onSave(data)
        }
        dismiss()
    }

    private func zoomOut() {
        adjustZoom(by: -0.15)
    }

    private func zoomIn() {
        adjustZoom(by: 0.15)
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    private func adjustZoom(by delta: CGFloat) {
        scale = clampedScale(scale + delta)
        lastScale = scale
    }

    private func applyScrollWheelZoom(_ delta: CGFloat) {
        guard delta != 0 else { return }
        let step = delta > 0 ? 0.08 : -0.08
        adjustZoom(by: step)
    }

    private func resetCropTransform() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
