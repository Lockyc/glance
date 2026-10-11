import AppKit
import ImageIO
import UniformTypeIdentifiers

public struct ImageDecoder: ImageDecoding {
    public init() {}

    public func decode(_ url: URL, maxPixelSize: Int) -> Result<DecodedImage, DecodeError> {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .svg) == true { return decodeSVG(url, maxPixelSize: maxPixelSize) }
        return decodeRaster(url, type: type, maxPixelSize: maxPixelSize)
    }

    private func decodeRaster(_ url: URL, type: UTType?, maxPixelSize: Int) -> Result<DecodedImage, DecodeError> {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return .failure(.unreadable) }

        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let upright = orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        let target = min(maxPixelSize, max(width, height))

        func thumbnail(fromEmbedded: Bool) -> CGImage? {
            let mode = fromEmbedded ? kCGImageSourceCreateThumbnailFromImageIfAbsent : kCGImageSourceCreateThumbnailFromImageAlways
            let options: [CFString: Any] = [
                mode: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: target,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }

        // Camera RAW: a full demosaic takes ~0.5 s; the embedded JPEG preview is instant.
        // Accept it when it is at least half the size we need.
        var image: CGImage?
        if type?.conforms(to: .rawImage) == true, let embedded = thumbnail(fromEmbedded: true),
           max(embedded.width, embedded.height) * 2 >= target {
            image = embedded
        }
        guard let image = image ?? thumbnail(fromEmbedded: false) else { return .failure(.unreadable) }

        let animatable = [UTType.gif, .png, .webP].contains { type?.conforms(to: $0) == true }
        return .success(DecodedImage(url: url, cgImage: image, pixelSize: upright,
                                     isAnimated: animatable && CGImageSourceGetCount(source) > 1))
    }

    private func decodeSVG(_ url: URL, maxPixelSize: Int) -> Result<DecodedImage, DecodeError> {
        guard let svg = NSImage(contentsOf: url), svg.size.width > 0, svg.size.height > 0 else { return .failure(.unreadable) }
        let scale = CGFloat(maxPixelSize) / max(svg.size.width, svg.size.height)
        let width = max(1, Int((svg.size.width * scale).rounded()))
        let height = max(1, Int((svg.size.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return .failure(.unreadable) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        svg.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return .failure(.unreadable) }
        return .success(DecodedImage(url: url, cgImage: image, pixelSize: svg.size, isAnimated: false, isVector: true))
    }
}
