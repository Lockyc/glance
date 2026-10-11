import CoreGraphics
import Foundation

public struct DecodedImage {
    public let url: URL
    /// Upright, downsampled to the requested long side (never above native for raster).
    public let cgImage: CGImage
    /// Full-resolution upright size; for SVG, the document's nominal size.
    public let pixelSize: CGSize
    public let isAnimated: Bool

    public init(url: URL, cgImage: CGImage, pixelSize: CGSize, isAnimated: Bool) {
        self.url = url
        self.cgImage = cgImage
        self.pixelSize = pixelSize
        self.isAnimated = isAnimated
    }
}

public enum DecodeError: Error, Equatable {
    case unreadable
}

public protocol ImageDecoding {
    /// Synchronous; call off the main thread.
    func decode(_ url: URL, maxPixelSize: Int) -> Result<DecodedImage, DecodeError>
}
