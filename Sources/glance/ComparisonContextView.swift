import AppKit
import GlanceCore

/// Overlays a comparison window's viewer with the grid's edges: every variant across the top and
/// every shot down the left, the current ones highlighted, plus a minimap of the grid in the photo's
/// top-right corner. Clicking a label or a map cell opens that cell; clicks anywhere else fall through
/// to the viewer, and a click here never takes the keyboard from it.
final class ComparisonContextView: NSView {
    static let columnHeaderHeight: CGFloat = 24
    static let rowHeight: CGFloat = 24
    static var rowHeaderWidth: CGFloat { ComparisonGridViewController.labelWidth }
    static let mapMargin: CGFloat = 12
    private static let labelInset: CGFloat = 10
    private static let textHeight: CGFloat = 16

    var onSelect: ((Comparison.Cell) -> Void)?
    var current: Comparison.Cell? {
        didSet {
            map.current = current
            needsLayout = true
            update()
        }
    }

    private let comparison: Comparison
    private let map: MapView
    private(set) var columnLabels: [NSTextField]
    private(set) var rowLabels: [NSTextField]
    private let aboveMarker = ComparisonContextView.label("", alignment: .left)
    private let belowMarker = ComparisonContextView.label("", alignment: .left)

    init(comparison: Comparison) {
        self.comparison = comparison
        map = MapView(comparison: comparison)
        columnLabels = comparison.variants.map { Self.label($0.label, alignment: .center) }
        rowLabels = (0..<comparison.rows).map { Self.label(comparison.rowLabel($0), alignment: .left) }
        super.init(frame: .zero)
        for marker in [aboveMarker, belowMarker] { marker.textColor = .tertiaryLabelColor }
        (columnLabels + rowLabels + [aboveMarker, belowMarker]).forEach(addSubview)
        addSubview(map)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func label(_ text: String, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    override var isFlipped: Bool { true }

    // MARK: Geometry

    private var columnBand: CGRect { CGRect(x: 0, y: 0, width: bounds.width, height: Self.columnHeaderHeight) }
    private var rowBand: CGRect {
        CGRect(x: 0, y: Self.columnHeaderHeight, width: Self.rowHeaderWidth, height: max(0, bounds.height - Self.columnHeaderHeight))
    }

    func columnLabelFrame(_ column: Int) -> CGRect {
        let width = (bounds.width - Self.rowHeaderWidth) / CGFloat(max(comparison.columns, 1))
        return CGRect(x: Self.rowHeaderWidth + CGFloat(column) * width, y: 0, width: width, height: Self.columnHeaderHeight)
    }

    private var rowWindow: ComparisonHeaderLayout.Window {
        ComparisonHeaderLayout.visibleRows(current: current?.row ?? 0, rows: comparison.rows,
                                           capacity: Int(rowBand.height / Self.rowHeight))
    }

    /// The shown slots, top to bottom from just under the column header: an optional "more" marker,
    /// the windowed rows, another optional marker.
    private func slotFrame(_ slot: Int) -> CGRect {
        CGRect(x: 0, y: rowBand.minY + CGFloat(slot) * Self.rowHeight, width: Self.rowHeaderWidth, height: Self.rowHeight)
    }

    /// nil while the row is windowed out.
    func rowLabelFrame(_ row: Int) -> CGRect? {
        let window = rowWindow
        guard window.rows.contains(row) else { return nil }
        return slotFrame(row - window.rows.lowerBound + (window.markerAbove ? 1 : 0))
    }

    /// The photo area the map may cover, inside its margins.
    private var mapBound: CGSize {
        CGSize(width: bounds.width - Self.rowHeaderWidth - 2 * Self.mapMargin,
               height: bounds.height - Self.columnHeaderHeight - 2 * Self.mapMargin)
    }

    var mapFrame: CGRect {
        let size = ComparisonMapLayout.size(columns: comparison.columns, rows: comparison.rows, bound: mapBound)
        return CGRect(origin: CGPoint(x: bounds.width - Self.mapMargin - size.width, y: Self.columnHeaderHeight + Self.mapMargin), size: size)
    }

    /// A label's text frame inside its slot: vertically centred, inset from the slot's sides.
    private func textFrame(in slot: CGRect, inset: CGFloat) -> CGRect {
        CGRect(x: slot.minX + inset, y: slot.midY - Self.textHeight / 2, width: max(0, slot.width - 2 * inset), height: Self.textHeight)
    }

    // MARK: Layout and state

    override func layout() {
        super.layout()
        map.bound = mapBound
        map.frame = mapFrame
        for column in columnLabels.indices {
            columnLabels[column].frame = textFrame(in: columnLabelFrame(column), inset: 4)
        }
        let window = rowWindow
        for row in rowLabels.indices {
            let frame = rowLabelFrame(row)
            rowLabels[row].isHidden = frame == nil
            if let frame { rowLabels[row].frame = textFrame(in: frame, inset: Self.labelInset) }
        }
        aboveMarker.isHidden = !window.markerAbove
        aboveMarker.stringValue = "⋮ \(window.above) more"
        aboveMarker.frame = textFrame(in: slotFrame(0), inset: Self.labelInset)
        belowMarker.isHidden = !window.markerBelow
        belowMarker.stringValue = "⋮ \(window.below) more"
        belowMarker.frame = textFrame(in: slotFrame(window.slots - 1), inset: Self.labelInset)
        update()
    }

    /// Current: full-strength; a label whose cell is empty in the current shot or variant: dimmed.
    private func update() {
        guard let current else { return }
        for column in columnLabels.indices {
            let cell = Comparison.Cell(row: current.row, column: column)
            columnLabels[column].textColor = column == current.column ? .labelColor
                : comparison.file(at: cell) == nil ? .tertiaryLabelColor : .secondaryLabelColor
        }
        for row in rowLabels.indices {
            let cell = Comparison.Cell(row: row, column: current.column)
            rowLabels[row].textColor = row == current.row ? .labelColor
                : comparison.file(at: cell) == nil ? .tertiaryLabelColor : .secondaryLabelColor
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.09, alpha: 1).setFill()
        columnBand.fill()
        rowBand.fill()
        guard let current else { return }
        let accent = NSColor.controlAccentColor
        let column = columnLabelFrame(current.column)
        accent.withAlphaComponent(0.2).setFill()
        column.fill()
        accent.setFill()
        CGRect(x: column.minX, y: column.maxY - 2, width: column.width, height: 2).fill()
        if let row = rowLabelFrame(current.row) {
            accent.withAlphaComponent(0.2).setFill()
            row.fill()
            accent.setFill()
            CGRect(x: row.minX, y: row.minY, width: 2, height: row.height).fill()
        }
    }

    // MARK: Clicks

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        return columnBand.contains(local) || rowBand.contains(local) || mapFrame.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let current else { return }
        let point = convert(event.locationInWindow, from: nil)
        let target: Comparison.Cell?
        if mapFrame.contains(point) {
            target = ComparisonMapLayout.cell(at: CGPoint(x: point.x - mapFrame.minX, y: point.y - mapFrame.minY),
                                              columns: comparison.columns, rows: comparison.rows, bound: mapBound)
        } else if let column = columnLabels.indices.first(where: { columnLabelFrame($0).contains(point) }) {
            target = Comparison.Cell(row: current.row, column: column)
        } else if let row = rowWindow.rows.first(where: { rowLabelFrame($0)?.contains(point) == true }) {
            target = Comparison.Cell(row: row, column: current.column)
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
    var bound = ComparisonMapLayout.unbounded { didSet { needsDisplay = true } }

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
                let rect = ComparisonMapLayout.rect(of: cell, columns: comparison.columns, rows: comparison.rows, bound: bound)
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
