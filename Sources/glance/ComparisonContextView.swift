import AppKit
import GlanceCore

/// Overlays a comparison window's viewer: the current shot in every variant as a strip along the
/// bottom, and the whole grid as a minimap in the top-right corner. Clicks anywhere else fall
/// through to the viewer, and a click here never takes the keyboard from it.
final class ComparisonContextView: NSView {
    static let stripHeight: CGFloat = 76
    static let maxStripCellWidth: CGFloat = 96
    static let mapMargin: CGFloat = 12
    private static let inset: CGFloat = 6
    private static let cellHeight: CGFloat = 54

    var onSelect: ((Comparison.Cell) -> Void)?
    var current: Comparison.Cell? {
        didSet {
            map.current = current
            refresh()
        }
    }

    private let comparison: Comparison
    private let thumbnails: ThumbnailService
    private let band = NSView()
    private let map: MapView
    private(set) var stripCells: [ComparisonCellView]
    private let labels: [NSTextField]

    init(comparison: Comparison, thumbnails: ThumbnailService) {
        self.comparison = comparison
        self.thumbnails = thumbnails
        map = MapView(comparison: comparison)
        stripCells = comparison.variants.map { _ in ComparisonCellView() }
        labels = comparison.variants.map { variant in
            let label = NSTextField(labelWithString: variant.label)
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            return label
        }
        super.init(frame: .zero)
        band.wantsLayer = true
        band.layer?.backgroundColor = NSColor(white: 0.09, alpha: 1).cgColor
        addSubview(band)
        stripCells.forEach(addSubview)
        labels.forEach(addSubview)
        addSubview(map)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    private var cellWidth: CGFloat {
        let n = CGFloat(max(comparison.columns, 1))
        return min(Self.maxStripCellWidth, (bounds.width - 2 * Self.inset - Self.inset * (n - 1)) / n)
    }

    func stripFrame(column: Int) -> CGRect {
        let n = CGFloat(comparison.columns), width = cellWidth
        let left = (bounds.width - (n * width + (n - 1) * Self.inset)) / 2
        return CGRect(x: left + CGFloat(column) * (width + Self.inset), y: bounds.height - Self.stripHeight + Self.inset,
                      width: width, height: Self.cellHeight)
    }

    var mapFrame: CGRect {
        let size = ComparisonMapLayout.size(columns: comparison.columns, rows: comparison.rows)
        return CGRect(origin: CGPoint(x: bounds.width - Self.mapMargin - size.width, y: Self.mapMargin), size: size)
    }

    private var bandFrame: CGRect { CGRect(x: 0, y: bounds.height - Self.stripHeight, width: bounds.width, height: Self.stripHeight) }

    override func layout() {
        super.layout()
        band.frame = bandFrame
        map.frame = mapFrame
        for column in stripCells.indices {
            let frame = stripFrame(column: column)
            stripCells[column].frame = frame
            labels[column].frame = CGRect(x: frame.minX, y: frame.maxY, width: frame.width, height: Self.stripHeight - Self.inset - Self.cellHeight)
        }
        refresh()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        refresh()
    }

    /// Thumbnails are requested only while shown, so a comparison that stays in the grid decodes nothing extra.
    private func refresh() {
        guard let current, !isHiddenOrHasHiddenAncestor else { return }
        let pixels = Int((cellWidth * (window?.backingScaleFactor ?? 2)).rounded(.up))
        for column in stripCells.indices {
            let cell = Comparison.Cell(row: current.row, column: column)
            stripCells[column].configure(url: comparison.file(at: cell), pixelSize: pixels, service: thumbnails)
            stripCells[column].isSelected = cell == current
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        return bandFrame.contains(local) || mapFrame.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let target: Comparison.Cell?
        if mapFrame.contains(point) {
            target = ComparisonMapLayout.cell(at: CGPoint(x: point.x - mapFrame.minX, y: point.y - mapFrame.minY),
                                              columns: comparison.columns, rows: comparison.rows)
        } else if let current, let column = stripCells.indices.first(where: { stripFrame(column: $0).contains(point) }) {
            target = Comparison.Cell(row: current.row, column: column)
        } else {
            target = nil
        }
        guard let target, comparison.file(at: target) != nil else { return }
        onSelect?(target)
    }
}

/// The grid in miniature: the current cell in the accent colour, the rest of its row lighter, empty cells outlined.
private final class MapView: NSView {
    private let comparison: Comparison
    var current: Comparison.Cell? { didSet { needsDisplay = true } }

    init(comparison: Comparison) {
        self.comparison = comparison
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.6).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        for row in 0..<comparison.rows {
            for column in 0..<comparison.columns {
                let cell = Comparison.Cell(row: row, column: column)
                let rect = ComparisonMapLayout.rect(of: cell, columns: comparison.columns, rows: comparison.rows)
                guard comparison.file(at: cell) != nil else {
                    NSColor(white: 1, alpha: 0.25).setStroke()
                    NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
                    continue
                }
                let color: NSColor = cell == current ? .controlAccentColor
                    : row == current?.row ? NSColor(white: 0.55, alpha: 1) : NSColor(white: 0.35, alpha: 1)
                color.setFill()
                rect.fill()
            }
        }
    }
}
