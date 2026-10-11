import CoreGraphics
import Foundation

public enum HoverPreview {
    public static let delay: TimeInterval = 0.15
    /// Capped at 320 so `side(tileSide:)` (≤ 480) always exceeds the tile it enlarges.
    public static let tileSideRange: ClosedRange<CGFloat> = 64...320
    public static let defaultTileSide: CGFloat = 160

    public static func side(tileSide: CGFloat) -> CGFloat { min(tileSide * 2.5, 480) }

    /// The image's aspect fitted in a `side` square, centred on `tile`, shrunk and shifted to stay in `bounds`.
    public static func frame(around tile: CGRect, imageSize: CGSize, side: CGFloat, bounds: CGRect) -> CGRect {
        let aspect = imageSize.width > 0 && imageSize.height > 0 ? imageSize.width / imageSize.height : 1
        var size = aspect >= 1 ? CGSize(width: side, height: side / aspect) : CGSize(width: side * aspect, height: side)
        let shrink = min(1, bounds.width / size.width, bounds.height / size.height)
        size = CGSize(width: size.width * shrink, height: size.height * shrink)
        let x = min(max(tile.midX - size.width / 2, bounds.minX), bounds.maxX - size.width)
        let y = min(max(tile.midY - size.height / 2, bounds.minY), bounds.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
