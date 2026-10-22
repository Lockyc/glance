import AppKit
import GlanceCore

final class GridViewController: NSViewController, BrowserGrid, NSCollectionViewDataSource, ZoomActions {
    var onOpen: ((Int) -> Void)?
    var onExit: (() -> Void)?

    private static let tileSideKey = "gridTileSide"

    private let model: FolderModel
    private let thumbnails: ThumbnailService
    private let scrollView = NSScrollView()
    private let collectionView = GridCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private let preview = HoverPreviewView()
    private lazy var previewer = HoverPreviewer(preview: preview, thumbnails: thumbnails)
    /// The file list and its month sections as last loaded into the collection view; items and
    /// old selections resolve against these, never against a model that may have moved on.
    private var listed: [URL] = []
    private var sections = MonthSections(dates: [], count: 0)

    init(model: FolderModel, thumbnails: ThumbnailService) {
        self.model = model
        self.thumbnails = thumbnails
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var firstResponderView: NSView { collectionView }

    var selectedFiles: [URL] {
        collectionView.selectionIndexPaths.compactMap(sections.index(for:)).sorted()
            .compactMap { listed.indices.contains($0) ? listed[$0] : nil }
    }

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
        layout.sectionHeadersPinToVisibleBounds = true
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [NSColor(white: 0.08, alpha: 1)]
        collectionView.register(ThumbnailItem.self, forItemWithIdentifier: ThumbnailItem.identifier)
        collectionView.register(MonthHeaderView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                withIdentifier: MonthHeaderView.identifier)
        collectionView.onActivate = { [weak self] path in
            guard let self, let index = self.sections.index(for: path) else { return }
            self.onOpen?(index)
        }
        collectionView.onStep = { [weak self] in self?.step($0) }
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
        load()
        reveal(model.currentIndex)
    }

    /// Snapshots the model into the collection view: files, month sections, header height.
    private func load() {
        listed = model.files
        sections = MonthSections(dates: model.dates, count: model.files.count)
        layout.headerReferenceSize = NSSize(width: 0, height: model.dates.isEmpty ? 0 : MonthHeaderView.height)
        collectionView.reloadData()
    }

    /// After the folder changed: the selection follows its file and the scroll position stays put,
    /// so files arriving mid-browse never yank the grid.
    func reload() {
        hidePreview()
        let selected = collectionView.selectionIndexPaths.compactMap(sections.index(for:)).compactMap { listed.indices.contains($0) ? listed[$0] : nil }
        let origin = scrollView.contentView.bounds.origin
        load()
        let kept = selected.compactMap { model.files.firstIndex(of: $0) }
        let fallback = model.currentIndex.map { [$0] } ?? []
        collectionView.selectionIndexPaths = Set((kept.isEmpty ? fallback : kept).map(sections.indexPath(for:)))
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func reveal(_ index: Int?) {
        guard let index, listed.indices.contains(index) else { return }
        let path = sections.indexPath(for: index)
        collectionView.selectionIndexPaths = [path]
        collectionView.scrollToItems(at: [path], scrollPosition: .centeredVertically)
    }

    /// ←/→: the next or previous tile in the flat order, across month boundaries; stops at the ends.
    private func step(_ delta: Int) {
        guard !listed.isEmpty else { return }
        let current = collectionView.selectionIndexPaths.first.flatMap(sections.index(for:)) ?? model.currentIndex ?? 0
        let path = sections.indexPath(for: min(max(current + delta, 0), listed.count - 1))
        collectionView.selectionIndexPaths = [path]
        collectionView.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.sections.count }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        sections.sections[section].range.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ThumbnailItem.identifier, for: indexPath) as! ThumbnailItem
        item.configure(url: listed[sections.index(for: indexPath)!], pixelSize: thumbnailPixels, service: thumbnails)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: MonthHeaderView.identifier, for: indexPath) as! MonthHeaderView
        header.configure(sections.sections[indexPath.section].title)
        return header
    }

    @objc func zoomIn(_ sender: Any?) { tileSide *= 1.25 }
    @objc func zoomOut(_ sender: Any?) { tileSide /= 1.25 }

    override func mouseMoved(with event: NSEvent) {
        let index = collectionView.indexPathForItem(at: collectionView.convert(event.locationInWindow, from: nil)).flatMap(sections.index(for:))
        previewer.hover(over: index) { [weak self] in self?.hoverTarget(at: index) }
    }

    override func mouseExited(with event: NSEvent) { hidePreview() }

    private func hoverTarget(at index: Int?) -> HoverTarget? {
        guard let index, listed.indices.contains(index),
              let item = collectionView.item(at: sections.indexPath(for: index)) as? ThumbnailItem else { return nil }
        let side = HoverPreview.side(tileSide: tileSide)
        return HoverTarget(url: listed[index], tile: view.convert(item.imageRect, from: item.view), image: item.image, side: side,
                           bounds: view.bounds.insetBy(dx: 8, dy: 8), pixels: Int((side * backingScale).rounded(.up)))
    }

    @objc private func hidePreview() { previewer.hide() }
}
