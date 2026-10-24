import AppKit
import GlanceCore

/// One comparison cell: the image aspect-fitted in the whole cell, TV static until its first
/// thumbnail arrives, or a muted fill when the variant has no file for this shot, so every cell
/// keeps the same size.
final class ComparisonCellView: NSView {
    private let imageLayer = CALayer()
    private let staticLayer = StaticLayer()
    private(set) var isLoading = false {
        didSet { staticLayer.isAnimating = isLoading }
    }
    private var request: Operation?
    private var requestedPixels = 0
    private(set) var url: URL?
    private(set) var image: CGImage?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.cornerRadius = 4
        imageLayer.masksToBounds = true
        imageLayer.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
        imageLayer.borderColor = NSColor.controlAccentColor.cgColor
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "borderWidth": NSNull()]
        imageLayer.addSublayer(staticLayer)
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The image area, in this view's coordinates.
    var imageRect: CGRect { bounds }

    override func layout() {
        super.layout()
        imageLayer.frame = imageRect
        staticLayer.frame = imageLayer.bounds
    }

    var isSelected = false {
        didSet { imageLayer.borderWidth = isSelected ? 3 : 0 }
    }

    /// Re-requests only for a different file or a larger size, so a resize never re-decodes downward.
    func configure(url: URL?, pixelSize: Int, service: ThumbnailService) {
        guard url != self.url || pixelSize > requestedPixels else { return }
        if url != self.url {
            image = nil
            imageLayer.contents = nil
        }
        request?.cancel()
        self.url = url
        requestedPixels = pixelSize
        toolTip = url?.lastPathComponent
        imageLayer.backgroundColor = NSColor(white: 1, alpha: url == nil ? 0.03 : 0.06).cgColor
        isLoading = url != nil && image == nil
        guard let url else { request = nil; return }
        request = service.request(url, pixelSize: pixelSize) { [weak self] result in
            guard let self, self.url == url else { return }
            self.isLoading = false
            switch result {
            case .success(let image):
                self.image = image
                self.imageLayer.contentsGravity = .resizeAspect
                self.imageLayer.contents = image
            case .failure:
                self.imageLayer.contentsGravity = .center
                self.imageLayer.contents = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Can't open")
            }
        }
    }
}
