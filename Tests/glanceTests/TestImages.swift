import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A `width`×`height` PNG at `url`, filled with `color` (transparent when nil) around a centred
/// inner rectangle in a contrasting colour, so aspect-fit shows in a render. The folder must exist.
func writeTestPNG(to url: URL, width: Int = 8, height: Int = 8, color: CGColor? = nil) {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let color, let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components {
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let luminance = 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]
        ctx.setFillColor(gray: luminance > 0.5 ? 0 : 1, alpha: 1)
        ctx.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
    }
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}
