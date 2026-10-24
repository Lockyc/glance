import AppKit
import GlanceCore

/// The comparison grid: variants as columns under a pinned header, shots as rows with their
/// labels in a left column. Every cell is the same size; an empty one stays in place.
final class ComparisonGridViewController: NSViewController, BrowserGrid, ZoomActions {
    var onOpen: ((Int) -> Void)?
    var onExit: (() -> Void)?

    private static let minimumSideKey = "comparisonMinimumSide"
    static let spacing: CGFloat = 12
    static let inset: CGFloat = 16
    static let labelWidth: CGFloat = 120
    static let headerHeight: CGFloat = 28

    private let comparison: Comparison
    private let thumbnails: ThumbnailService
    private let scrollView = NSScrollView()
    private let header = NSView()
    private let grid: ComparisonGridView
    private var headerLabels: [NSTextField] = []
    private let preview = HoverPreviewView()
    private lazy var previewer = HoverPreviewer(preview: preview, thumbnails: thumbnails)
    private var cellSize: CGSize
    /// Thumbnails wait for the first layout: a request at the provisional size would be decoded and thrown away.
    private var laidOut = false

    init(comparison: Comparison, thumbnails: ThumbnailService) {
        self.comparison = comparison
        self.thumbnails = thumbnails
        grid = ComparisonGridView(comparison: comparison)
        let side = Self.storedMinimumSide
        cellSize = CGSize(width: side, height: side)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var firstResponderView: NSView { grid }

    var selectedFiles: [URL] { comparison.file(at: grid.selection).map { [$0] } ?? [] }

    private static var storedMinimumSide: CGFloat {
        let stored = UserDefaults.standard.double(forKey: minimumSideKey)
        return stored > 0 ? stored : ComparisonLayout.defaultMinimumSide
    }

    private var minimumSide: CGFloat {
        get { Self.storedMinimumSide }
        set {
            let range = ComparisonLayout.minimumSideRange
            UserDefaults.standard.set(min(range.upperBound, max(range.lowerBound, newValue)), forKey: Self.minimumSideKey)
            hidePreview()
            view.needsLayout = true
        }
    }

    private var backingScale: CGFloat { view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    /// Rounded up to a 256 px step, so a live resize re-decodes a handful of times, not every frame.
    private var thumbnailPixels: Int {
        let needed = Int((max(cellSize.width, cellSize.height) * backingScale).rounded(.up))
        return (needed + 255) / 256 * 256
    }

    override func loadView() {
        let root = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        for variant in comparison.variants {
            let label = NSTextField(labelWithString: variant.label)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            header.addSubview(label)
            headerLabels.append(label)
        }
        grid.onActivate = { [weak self] cell in
            guard let self, let index = self.comparison.cells.firstIndex(of: cell) else { return }
            self.onOpen?(index)
        }
        grid.onExit = { [weak self] in self?.onExit?() }
        scrollView.documentView = grid
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.08, alpha: 1)
        root.addSubview(header)
        root.addSubview(scrollView)
        root.addSubview(preview)
        scrollView.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        view = root
        reload()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let bounds = view.bounds
        header.frame = NSRect(x: 0, y: bounds.height - Self.headerHeight, width: bounds.width, height: Self.headerHeight)
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - Self.headerHeight))
        let available = scrollView.contentSize
        let chrome = Self.inset * 2 + Self.labelWidth + Self.spacing
        cellSize = ComparisonLayout.cellSize(columns: comparison.columns, rows: comparison.rows,
                                             available: CGSize(width: available.width - chrome, height: available.height - Self.inset * 2),
                                             minimumSide: minimumSide, spacing: Self.spacing)
        grid.layOut(cellSize: cellSize)
        laidOut = true
        configureCells()
        positionHeader()
    }

    /// The comparison never changes; this refreshes the cells' thumbnails and the selection.
    func reload() {
        hidePreview()
        configureCells()
    }

    func reveal(_ index: Int?) {
        guard let index, comparison.cells.indices.contains(index) else { return }
        grid.selection = comparison.cells[index]
        grid.scrollSelectionToVisible()
    }

    private func configureCells() {
        guard laidOut else { return }
        let pixels = thumbnailPixels
        for (i, cell) in grid.cellViews.enumerated() {
            cell.configure(url: comparison.file(at: grid.cell(at: i)), pixelSize: pixels, service: thumbnails)
        }
    }

    /// Header labels sit over their columns and follow the grid's horizontal scroll.
    private func positionHeader() {
        let offset = scrollView.contentView.bounds.origin.x
        for (column, label) in headerLabels.enumerated() {
            let x = grid.columnX(column) - offset
            let height = label.intrinsicContentSize.height
            label.frame = NSRect(x: x, y: (Self.headerHeight - height) / 2, width: cellSize.width, height: height)
        }
    }

    @objc private func scrolled() {
        hidePreview()
        positionHeader()
    }

    @objc func zoomIn(_ sender: Any?) { minimumSide *= 1.25 }
    @objc func zoomOut(_ sender: Any?) { minimumSide /= 1.25 }

    override func mouseMoved(with event: NSEvent) {
        let cell = grid.presentCell(at: grid.convert(event.locationInWindow, from: nil))
        previewer.hover(over: cell) { [weak self] in self?.hoverTarget(at: cell) }
    }

    override func mouseExited(with event: NSEvent) { hidePreview() }

    /// No preview when the cell is already at least as large as the preview would be.
    private func hoverTarget(at cell: Comparison.Cell?) -> HoverTarget? {
        guard let cell, let url = comparison.file(at: cell) else { return nil }
        let cellView = grid.cellViews[cell.row * comparison.columns + cell.column]
        let longest = max(cellSize.width, cellSize.height)
        let side = HoverPreview.side(tileSide: min(longest, HoverPreview.tileSideRange.upperBound))
        guard side > longest else { return nil }
        return HoverTarget(url: url, tile: view.convert(cellView.imageRect, from: cellView), image: cellView.image, side: side,
                           bounds: view.bounds.insetBy(dx: 8, dy: 8), pixels: Int((side * backingScale).rounded(.up)))
    }

    @objc private func hidePreview() { previewer.hide() }
}

/// The grid's document view and first responder: arrows move the selection in 2D (onto empty
/// cells too), Return or a click opens a present cell, G/Space/Esc go back to the viewer.
final class ComparisonGridView: NSView {
    var onActivate: ((Comparison.Cell) -> Void)?
    var onExit: (() -> Void)?

    private let comparison: Comparison
    /// Row-major, `rows × columns`, empty cells included.
    let cellViews: [ComparisonCellView]
    private let rowLabels: [NSTextField]
    private var cellSize = CGSize.zero

    var selection = Comparison.Cell(row: 0, column: 0) {
        didSet {
            guard selection != oldValue else { return }
            cellView(oldValue)?.isSelected = false
            cellView(selection)?.isSelected = true
        }
    }

    init(comparison: Comparison) {
        self.comparison = comparison
        cellViews = (0..<(comparison.rows * comparison.columns)).map { _ in ComparisonCellView() }
        rowLabels = (0..<comparison.rows).map { row in
            let label = NSTextField(labelWithString: comparison.rowLabel(row))
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.lineBreakMode = .byTruncatingMiddle
            return label
        }
        super.init(frame: .zero)
        cellViews.forEach(addSubview)
        rowLabels.forEach(addSubview)
        cellView(selection)?.isSelected = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func cell(at index: Int) -> Comparison.Cell {
        Comparison.Cell(row: index / comparison.columns, column: index % comparison.columns)
    }

    private func cellView(_ cell: Comparison.Cell) -> ComparisonCellView? {
        guard cell.row >= 0, cell.row < comparison.rows, cell.column >= 0, cell.column < comparison.columns else { return nil }
        return cellViews[cell.row * comparison.columns + cell.column]
    }

    // MARK: Geometry

    typealias Metrics = ComparisonGridViewController

    func columnX(_ column: Int) -> CGFloat {
        Metrics.inset + Metrics.labelWidth + Metrics.spacing + CGFloat(column) * (cellSize.width + Metrics.spacing)
    }

    private func rowY(_ row: Int) -> CGFloat { Metrics.inset + CGFloat(row) * (cellSize.height + Metrics.spacing) }

    private func frame(of cell: Comparison.Cell) -> NSRect {
        NSRect(x: columnX(cell.column), y: rowY(cell.row), width: cellSize.width, height: cellSize.height)
    }

    func layOut(cellSize: CGSize) {
        self.cellSize = cellSize
        let columns = CGFloat(comparison.columns), rows = CGFloat(comparison.rows)
        let width = columnX(0) + columns * cellSize.width + max(0, columns - 1) * Metrics.spacing + Metrics.inset
        let height = Metrics.inset * 2 + rows * cellSize.height + max(0, rows - 1) * Metrics.spacing
        setFrameSize(NSSize(width: width, height: height))
        for (i, view) in cellViews.enumerated() { view.frame = frame(of: cell(at: i)) }
        for (row, label) in rowLabels.enumerated() {
            let labelHeight = label.intrinsicContentSize.height
            label.frame = NSRect(x: Metrics.inset, y: rowY(row) + (cellSize.height - labelHeight) / 2,
                                 width: Metrics.labelWidth, height: labelHeight)
        }
    }

    /// The cell under `point` (this view's coordinates) when it holds a file.
    func presentCell(at point: NSPoint) -> Comparison.Cell? {
        guard let index = cellViews.firstIndex(where: { $0.frame.contains(point) }) else { return nil }
        let cell = cell(at: index)
        return comparison.file(at: cell) == nil ? nil : cell
    }

    func scrollSelectionToVisible() {
        guard cellSize != .zero else { return }
        scrollToVisible(frame(of: selection).insetBy(dx: -Metrics.spacing, dy: -Metrics.spacing))
    }

    // MARK: Input

    private func move(_ move: Comparison.Move) {
        selection = comparison.gridStep(from: selection, move)
        scrollSelectionToVisible()
    }

    private func activate(_ cell: Comparison.Cell) {
        guard comparison.file(at: cell) != nil else { return }
        onActivate?(cell)
    }

    override func keyDown(with event: NSEvent) {
        switch GridKey.from(event) {
        case .activate: activate(selection)
        case .exit: onExit?()
        case .toggleFullScreen: window?.toggleFullScreen(nil)
        case .editInExcerpt: _ = window?.tryToPerform(#selector(BrowserWindowController.editInExcerpt(_:)), with: nil)
        case .arrow(let direction): move(direction)
        case nil: super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = cellViews.firstIndex(where: { $0.frame.contains(point) }) else { return super.mouseDown(with: event) }
        window?.makeFirstResponder(self)
        selection = cell(at: index)
        activate(selection)
    }
}
