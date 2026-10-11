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
        view = root
        applyTileSize()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        scrollView.frame = view.bounds
    }

    private func applyTileSize() {
        layout.itemSize = NSSize(width: tileSide, height: tileSide + ThumbnailItem.captionHeight)
        collectionView.reloadData()
        reveal(model.currentIndex)
    }

    func reload() {
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
}
