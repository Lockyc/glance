import AppKit

extension CALayer {
    /// A tile's decode result: the image fitted to the tile, or — for a file that can't be
    /// opened (`nil`) — a light warning glyph. Shared by the thumbnail and comparison grids.
    func showThumbnail(_ image: CGImage?) {
        if let image {
            contentsGravity = .resizeAspect
            contents = image
        } else {
            contentsGravity = .center
            contents = Self.cantOpenGlyph
        }
    }

    /// A symbol image is a template, which a layer never tints, so it would draw black on
    /// the dark tile; the glyph is drawn tinted into its own image once instead.
    private static let cantOpenGlyph: NSImage = {
        let symbol = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Can't open")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 24, weight: .regular))!
        return NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor(white: 1, alpha: 0.45).set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }()
}
