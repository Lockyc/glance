import CoreGraphics

/// Where an image sits in the viewer. `scale` is device pixels per image pixel, so 1 means
/// actual size on any display. Geometry is AppKit-style: origin bottom-left, view sizes in points.
public struct Viewport: Equatable {
    public static let maxScale: CGFloat = 32
    /// Largest long side an SVG is re-rasterised at when zoomed: 8192² × 4 bytes ≈ 256 MB.
    public static let vectorPixelCeiling = 8192

    public private(set) var imageSize: CGSize
    public private(set) var viewSize: CGSize
    public private(set) var backingScale: CGFloat
    public private(set) var scale: CGFloat
    public private(set) var center: CGPoint
    public private(set) var isFit: Bool

    public static func fit(imageSize: CGSize, viewSize: CGSize, backingScale: CGFloat) -> Viewport {
        var v = Viewport(imageSize: imageSize, viewSize: viewSize, backingScale: backingScale, scale: 1,
                         center: CGPoint(x: imageSize.width / 2, y: imageSize.height / 2), isFit: true)
        v.scale = v.fitScale
        return v
    }

    /// The largest scale showing the whole image, never above actual size.
    public var fitScale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(1, viewSize.width * backingScale / imageSize.width, viewSize.height * backingScale / imageSize.height)
    }

    private var pointsPerPixel: CGFloat { scale / backingScale }

    public var imageFrame: CGRect {
        let k = pointsPerPixel
        return CGRect(x: viewSize.width / 2 - center.x * k, y: viewSize.height / 2 - center.y * k,
                      width: imageSize.width * k, height: imageSize.height * k)
    }

    /// Long side, in device pixels, of a bitmap that shows the current zoom at full detail:
    /// never more than a raster file holds, nor more than `vectorPixelCeiling` for a vector.
    public func detailPixels(isVector: Bool) -> Int {
        let onScreen = Int((max(imageFrame.width, imageFrame.height) * backingScale).rounded(.up))
        let limit = isVector ? Self.vectorPixelCeiling : Int(max(imageSize.width, imageSize.height).rounded(.up))
        return min(onScreen, limit)
    }

    public func fitted() -> Viewport { .fit(imageSize: imageSize, viewSize: viewSize, backingScale: backingScale) }

    public func zoomed(to newScale: CGFloat, about point: CGPoint) -> Viewport {
        let clampedScale = min(Self.maxScale, max(fitScale, newScale))
        let k = pointsPerPixel
        let k2 = clampedScale / backingScale
        let dx = point.x - viewSize.width / 2
        let dy = point.y - viewSize.height / 2
        let anchor = CGPoint(x: center.x + dx / k, y: center.y + dy / k)
        var v = self
        v.scale = clampedScale
        v.center = CGPoint(x: anchor.x - dx / k2, y: anchor.y - dy / k2)
        v.isFit = abs(clampedScale - fitScale) < 1e-6
        return v.clamped()
    }

    public func zoomed(by factor: CGFloat, about point: CGPoint) -> Viewport {
        zoomed(to: scale * factor, about: point)
    }

    public func panned(by delta: CGSize) -> Viewport {
        var v = self
        v.center.x -= delta.width / pointsPerPixel
        v.center.y -= delta.height / pointsPerPixel
        return v.clamped()
    }

    public func resized(to newViewSize: CGSize, backingScale newBacking: CGFloat) -> Viewport {
        if isFit { return .fit(imageSize: imageSize, viewSize: newViewSize, backingScale: newBacking) }
        var v = self
        v.viewSize = newViewSize
        v.backingScale = newBacking
        v.scale = max(v.scale, v.fitScale)
        return v.clamped()
    }

    /// An axis smaller than the view is centred; a larger one may not expose empty space.
    private func clamped() -> Viewport {
        let k = pointsPerPixel
        func clamp(_ c: CGFloat, image: CGFloat, view: CGFloat) -> CGFloat {
            if image * k <= view { return image / 2 }
            let half = view / 2 / k
            return min(max(c, half), image - half)
        }
        var v = self
        v.center = CGPoint(x: clamp(center.x, image: imageSize.width, view: viewSize.width),
                           y: clamp(center.y, image: imageSize.height, view: viewSize.height))
        return v
    }
}
