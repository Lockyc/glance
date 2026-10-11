import AppKit
import GlanceCore

final class GridViewController: NSViewController, NSCollectionViewDataSource, ZoomActions {
    var onOpen: ((Int) -> Void)?
    var onExit: (() -> Void)?

    private static let tileSideKey = "gridTileSide"

    private let model: FolderModel
    private let thumbnails: ThumbnailService
    private let scrollView = NSScrollView()
    private let collectionView = GridCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private let preview = HoverPreviewView()
    private var hoverTimer: Timer?
    private var hoveredIndex: Int?
    private var previewRequest: Operation?

    init(model: FolderModel, thumbnails: ThumbnailService) {
        self.model = model
        self.thumbnails = thumbnails
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var firstResponderView: NSView { collectionView }

    private var tileSide: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: Self.tileSideKey)
            return stored > 0 ? stored : HoverPreview.defaultTileSide
        }
        set {
            let range = HoverPreview.tileSideRange
            UserDefaults.standard.set(min(range.upperBound, max(range.lowerBound, newValue)), forKey: Self.tileSideKey)
            applyTileSize()
        }
    }

    private var backingScale: CGFloat { view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
    private var thumbnailPixels: Int { Int((tileSide * backingScale).rounded(.up)) }

    override func loadView() {
        let root = NSView()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.isSelectable = true
        collectionView.backgroundColors = [NSColor(white: 0.08, alpha: 1)]
        collectionView.register(ThumbnailItem.self, forItemWithIdentifier: ThumbnailItem.identifier)
        collectionView.onActivate = { [weak self] in self?.onOpen?($0) }
        collectionView.onExit = { [weak self] in self?.onExit?() }
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        root.addSubview(scrollView)
        root.addSubview(preview)
        scrollView.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(hidePreview), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        view = root
        applyTileSize()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        scrollView.frame = view.bounds
    }

    private func applyTileSize() {
        hidePreview()
        layout.itemSize = NSSize(width: tileSide, height: tileSide + ThumbnailItem.captionHeight)
        collectionView.reloadData()
        reveal(model.currentIndex)
    }

    func reload() {
        hidePreview()
        collectionView.reloadData()
        reveal(model.currentIndex)
    }

    func reveal(_ index: Int?) {
        guard let index, model.files.indices.contains(index) else { return }
        let path = IndexPath(item: index, section: 0)
        collectionView.selectionIndexPaths = [path]
        collectionView.scrollToItems(at: [path], scrollPosition: .centeredVertically)
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        model.files.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ThumbnailItem.identifier, for: indexPath) as! ThumbnailItem
        item.configure(url: model.files[indexPath.item], pixelSize: thumbnailPixels, service: thumbnails)
        return item
    }

    @objc func zoomIn(_ sender: Any?) { tileSide *= 1.25 }
    @objc func zoomOut(_ sender: Any?) { tileSide /= 1.25 }

    override func mouseMoved(with event: NSEvent) {
        let index = collectionView.indexPathForItem(at: collectionView.convert(event.locationInWindow, from: nil))?.item
        guard index != hoveredIndex else { return }
        hidePreview()
        hoveredIndex = index
        guard let index else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: HoverPreview.delay, repeats: false) { [weak self] _ in
            self?.showPreview(index)
        }
    }

    override func mouseExited(with event: NSEvent) { hidePreview() }

    private func showPreview(_ index: Int) {
        guard model.files.indices.contains(index),
              let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? ThumbnailItem else { return }
        let side = HoverPreview.side(tileSide: tileSide)
        let tile = view.convert(item.imageRect, from: item.view)
        let aspectSource = item.image.map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: 1, height: 1)
        preview.show(item.image, frame: HoverPreview.frame(around: tile, imageSize: aspectSource, side: side, bounds: view.bounds.insetBy(dx: 8, dy: 8)))
        let pixels = Int((side * backingScale).rounded(.up))
        previewRequest = thumbnails.request(model.files[index], pixelSize: pixels) { [weak self] result in
            guard let self, self.hoveredIndex == index, case .success(let image) = result else { return }
            self.preview.update(image)
        }
    }

    /// Also clears `hoveredIndex`, so after a scroll the next mouse move re-arms the preview.
    @objc private func hidePreview() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        previewRequest?.cancel()
        previewRequest = nil
        hoveredIndex = nil
        preview.hide()
    }
}
