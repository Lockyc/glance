import AppKit
import GlanceCore

/// A square image area with the filename under it. The filename shows from the start, so a
/// tile looks the same shape while loading, loaded, or failed.
final class ThumbnailItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailItem")
    static let captionHeight: CGFloat = 20

    private let imageLayer = CALayer()
    private let caption = NSTextField(labelWithString: "")
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
    }

    override var isSelected: Bool {
        didSet { imageLayer.borderWidth = isSelected ? 3 : 0 }
    }

    func configure(url: URL, pixelSize: Int, service: ThumbnailService) {
        self.url = url
        caption.stringValue = url.lastPathComponent
        view.toolTip = url.lastPathComponent
        request = service.request(url, pixelSize: pixelSize) { [weak self] result in
            guard let self, self.url == url else { return }
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

    override func prepareForReuse() {
        super.prepareForReuse()
        request?.cancel()
        request = nil
        url = nil
        image = nil
        imageLayer.contents = nil
    }
}
