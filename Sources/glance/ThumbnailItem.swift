import AppKit
import GlanceCore

/// A square image area with the filename under it. The filename shows from the start, so a
/// tile looks the same shape while loading (TV static), loaded, or failed.
final class ThumbnailItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailItem")
    static let captionHeight: CGFloat = 20

    private let imageLayer = CALayer()
    private let caption = NSTextField(labelWithString: "")
    private let staticLayer = StaticLayer()
    private(set) var isLoading = false {
        didSet { staticLayer.isAnimating = isLoading }
    }
    private var request: Operation?
    private var url: URL?
    private(set) var image: CGImage?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        imageLayer.cornerRadius = 4
        imageLayer.masksToBounds = true
        imageLayer.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
        imageLayer.borderColor = NSColor.controlAccentColor.cgColor
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        imageLayer.addSublayer(staticLayer)
        root.layer?.addSublayer(imageLayer)
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingMiddle
        root.addSubview(caption)
        view = root
    }

    /// The square image area, in the item view's coordinates (origin bottom-left).
    var imageRect: CGRect {
        let side = view.bounds.width
        return CGRect(x: 0, y: view.bounds.height - side, width: side, height: side)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        imageLayer.frame = imageRect
        caption.frame = NSRect(x: 0, y: 0, width: view.bounds.width, height: Self.captionHeight - 4)
        staticLayer.frame = imageLayer.bounds
    }

    override var isSelected: Bool {
        didSet { imageLayer.borderWidth = isSelected ? 3 : 0 }
    }

    func configure(url: URL, pixelSize: Int, service: ThumbnailService) {
        self.url = url
        caption.stringValue = url.lastPathComponent
        view.toolTip = url.lastPathComponent
        isLoading = true
        request = service.request(url, pixelSize: pixelSize) { [weak self] result in
            guard let self, self.url == url else { return }
            self.isLoading = false
            if case .success(let image) = result { self.image = image }
            self.imageLayer.showThumbnail(try? result.get())
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        request?.cancel()
        request = nil
        isLoading = false
        url = nil
        image = nil
        imageLayer.contents = nil
    }
}
