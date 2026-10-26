import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Crops and bounds a studio logo the same way a profile photo is prepared.
enum StudioLogoProcessor {
    static let exportSide: CGFloat = 512
    nonisolated static let sourceMaxLongEdgePixels = 2048
    nonisolated private static let sourceQuality: CGFloat = 0.85

    nonisolated static func boundedSourceJPEGData(from raw: Data) -> Data? {
        guard let downsampled = downsampledCGImage(from: raw, maxPixelSize: sourceMaxLongEdgePixels)
        else { return raw }
        return jpegData(from: downsampled, quality: sourceQuality) ?? raw
    }

    nonisolated static func pixelLongEdge(of data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return max(width, height)
    }

    nonisolated static func exceedsSourceCap(_ data: Data) -> Bool {
        guard let longEdge = pixelLongEdge(of: data) else { return false }
        return longEdge > sourceMaxLongEdgePixels
    }

    nonisolated static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func croppedJPEGData(
        from image: NSImage,
        offset: CGSize,
        scale: CGFloat,
        cropSide: CGFloat
    ) -> Data? {
        guard let cgImage = cgImage(from: image) else { return nil }
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        return croppedJPEGData(
            from: cgImage,
            logicalSize: pixelSize,
            offset: offset,
            scale: scale,
            cropSide: cropSide
        )
    }

    static func croppedJPEGData(
        from cgImage: CGImage,
        logicalSize: CGSize,
        offset: CGSize,
        scale: CGFloat,
        cropSide: CGFloat
    ) -> Data? {
        let pixelScale = CGFloat(cgImage.width) / max(logicalSize.width, 1)
        let cropSidePixels = cropSide * pixelScale
        let offsetPixels = CGSize(width: offset.width * pixelScale, height: offset.height * pixelScale)
        let scaleFactor = max(scale, 0.1)

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let baseFitScale = min(cropSidePixels / imageWidth, cropSidePixels / imageHeight)
        let totalScale = baseFitScale * scaleFactor

        let drawWidth = imageWidth * totalScale
        let drawHeight = imageHeight * totalScale
        let originX = ((cropSidePixels - drawWidth) / 2) + offsetPixels.width
        let originY = ((cropSidePixels - drawHeight) / 2) - offsetPixels.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(exportSide),
            height: Int(exportSide),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: exportSide, height: exportSide))

        let clipScale = exportSide / cropSidePixels
        context.scaleBy(x: clipScale, y: clipScale)
        context.interpolationQuality = .high
        context.draw(
            cgImage,
            in: CGRect(x: originX, y: originY, width: drawWidth, height: drawHeight)
        )

        guard let output = context.makeImage() else { return nil }
        return jpegData(from: output, quality: 0.88)
    }

    static func cgImage(from nsImage: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    nonisolated private static func downsampledCGImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
