import AppKit
@testable import glance
import GlanceCore
import XCTest

/// The pixel size of every thumbnail decode.
final class RecordingDecoder: ImageDecoding {
    private let lock = NSLock()
    private var _sizes: [Int] = []
    var sizes: [Int] { lock.withLock { _sizes } }
    func decode(_ url: URL, maxPixelSize: Int) -> Result<DecodedImage, DecodeError> {
        lock.withLock { _sizes.append(maxPixelSize) }
        return ImageDecoder().decode(url, maxPixelSize: maxPixelSize)
    }
}

/// The comparison window: a variant × shot grid and a viewer that steps along rows and columns.
/// Fixture `a: [a1, a2]`, `b: [b1]`, `c: [c1, c2]` — the cell at (1,1) is empty.
final class ComparisonWindowTests: XCTestCase {
    private var dir: URL!
    private var model: FolderModel!
    private var controller: BrowserWindowController!
    private var window: NSWindow!
    private var decoder: RecordingDecoder!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        UserDefaults.standard.removeObject(forKey: BrowserWindowController.contextKey)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-comparison-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["a1", "a2", "b1", "c1", "c2"] { writeTestPNG(to: url(name)) }
        let comparison = Comparison(variants: [
            Variant(label: "a", files: [url("a1"), url("a2")]),
            Variant(label: "b", files: [url("b1")]),
            Variant(label: "c", files: [url("c1"), url("c2")]),
        ])
        model = FolderModel(folder: dir, files: comparison.files.map(FolderModel.canonical), current: nil, scope: .fixed)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)")
        decoder = RecordingDecoder()
        controller = BrowserWindowController(model: model, thumbnails: ThumbnailService(decoder: decoder, cacheDirectory: cache),
                                             startInGrid: true, comparison: comparison)
        window = try XCTUnwrap(controller.window)
        window.layoutIfNeeded()
    }

    override func tearDown() {
        controller.close()
        UserDefaults.standard.removeObject(forKey: BrowserWindowController.contextKey)
    }

    private func url(_ name: String) -> URL { dir.appendingPathComponent("\(name).png") }

    private func key(_ characters: String, _ keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    private var right: NSEvent { key(String(UnicodeScalar(NSRightArrowFunctionKey)!), 124) }
    private var up: NSEvent { key(String(UnicodeScalar(NSUpArrowFunctionKey)!), 126) }
    private var down: NSEvent { key(String(UnicodeScalar(NSDownArrowFunctionKey)!), 125) }
    private var esc: NSEvent { key("\u{1B}", 53) }
    private var enter: NSEvent { key("\r", 36) }

    private func press(_ event: NSEvent) { window.firstResponder?.keyDown(with: event) }

    private func cell(_ row: Int, _ column: Int) -> Comparison.Cell { Comparison.Cell(row: row, column: column) }

    func testOpensInTheGridOnTheFirstCell() throws {
        let grid = try XCTUnwrap(window.firstResponder as? ComparisonGridView)
        XCTAssertEqual(grid.selection, cell(0, 0))
        XCTAssertEqual(model.currentIndex, 0)
    }

    func testGridArrowsMoveIn2DAndReturnOpensOnlyPresentCells() throws {
        let grid = try XCTUnwrap(window.firstResponder as? ComparisonGridView)
        press(down)
        press(right)
        XCTAssertEqual(grid.selection, cell(1, 1))
        press(enter)
        XCTAssertTrue(window.firstResponder === grid, "an empty cell does not open")
        press(right)
        XCTAssertEqual(grid.selection, cell(1, 2))
        press(enter)
        XCTAssertTrue(window.firstResponder is ViewerView)
        XCTAssertEqual(model.current, url("c2"))
    }

    func testViewerArrowsFollowTheRowAndColumn() throws {
        let grid = try XCTUnwrap(window.firstResponder as? ComparisonGridView)
        press(down)
        press(right)
        press(right)
        XCTAssertEqual(grid.selection, cell(1, 2))
        press(enter)
        XCTAssertEqual(model.current, url("c2"))

        press(right)
        XCTAssertEqual(model.current, url("a2"), "wraps within the row and skips the empty cell")
        press(up)
        XCTAssertEqual(model.current, url("a1"))
        press(up)
        XCTAssertEqual(model.current, url("a1"), "stops at the top")
        press(right)
        XCTAssertEqual(model.current, url("b1"))
        press(down)
        XCTAssertEqual(model.current, url("b1"), "nothing below b1")
    }

    func testTitleNamesVariantAndRow() throws {
        press(enter)
        XCTAssertTrue(window.firstResponder is ViewerView)
        XCTAssertEqual(model.current, url("a1"))
        XCTAssertTrue(window.title.hasPrefix("a · "), window.title)
    }

    func testGSpaceEscReturnBetweenGridAndViewer() {
        press(enter)
        XCTAssertTrue(window.firstResponder is ViewerView)
        press(esc)
        XCTAssertTrue(window.firstResponder is ComparisonGridView, "Esc outside full screen shows the grid")
        press(esc)
        XCTAssertTrue(window.firstResponder is ViewerView, "Esc in the grid opens the current cell")
        press(key("g", 5))
        XCTAssertTrue(window.firstResponder is ComparisonGridView)
        press(key("g", 5))
        XCTAssertTrue(window.firstResponder is ViewerView)
        press(key(" ", 49))
        XCTAssertTrue(window.firstResponder is ComparisonGridView)
        press(key(" ", 49))
        XCTAssertTrue(window.firstResponder is ViewerView)
    }

    func testCellsSpinUntilTheirThumbnailLandsAndDecodeOnceAtTheLaidOutSize() throws {
        let grid = try XCTUnwrap(window.firstResponder as? ComparisonGridView)
        let present = grid.cellViews.filter { $0.url != nil }
        XCTAssertTrue(present.allSatisfy(\.isLoading))
        XCTAssertFalse(grid.cellViews[1 * 3 + 1].isLoading)
        let deadline = Date().addingTimeInterval(5)
        while present.contains(where: { $0.image == nil }), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertFalse(present.contains(where: \.isLoading))
        XCTAssertEqual(decoder.sizes.count, present.count, "one decode per cell, none at a provisional size")
    }

    // MARK: Context (headers + map) in the viewer

    private var viewer: ViewerView { controller.window!.contentView!.subviews.compactMap { $0 as? ViewerView }.first! }

    /// A single click at a point in the context view's coordinates, delivered to whatever the window hit-tests there.
    private func click(_ point: CGPoint, in context: ComparisonContextView) {
        let location = context.convert(point, to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let content = try! XCTUnwrap(window.contentView)
        content.hitTest(content.convert(location, from: nil))?.mouseDown(with: event)
    }

    private func click(_ frame: CGRect?) throws {
        let context = try XCTUnwrap(controller.context)
        let frame = try XCTUnwrap(frame)
        click(CGPoint(x: frame.midX, y: frame.midY), in: context)
    }

    /// The viewer's frame while the headers show: right of the row header, below the column header.
    private var insetViewerFrame: NSRect {
        let bounds = window.contentView!.bounds
        return NSRect(x: ComparisonContextView.rowHeaderWidth, y: 0, width: bounds.width - ComparisonContextView.rowHeaderWidth,
                      height: bounds.height - ComparisonContextView.columnHeaderHeight)
    }

    func testContextShowsInTheViewerOnly() throws {
        let context = try XCTUnwrap(controller.context)
        XCTAssertTrue(context.isHidden)
        press(enter)
        XCTAssertFalse(context.isHidden)
        XCTAssertEqual(viewer.frame, insetViewerFrame)
        press(esc)
        XCTAssertTrue(context.isHidden)
    }

    func testHeadersHighlightTheCurrentCell() throws {
        press(enter)
        press(down)
        XCTAssertEqual(model.current, url("a2"))
        let context = try XCTUnwrap(controller.context)
        XCTAssertEqual(context.columnLabels.map(\.stringValue), ["a", "b", "c"])
        XCTAssertEqual(context.columnLabels.map(\.textColor), [.labelColor, .tertiaryLabelColor, .secondaryLabelColor],
                       "current, empty in this shot, other")
        XCTAssertEqual(context.rowLabels.map(\.textColor), [.secondaryLabelColor, .labelColor])
    }

    func testClickingAColumnLabelOpensThatVariantInTheSameShot() throws {
        press(enter)
        try click(controller.context?.columnLabelFrame(2))
        XCTAssertEqual(model.current, url("c1"))
    }

    func testClickingARowLabelOpensThatShotInTheSameVariant() throws {
        press(enter)
        try click(controller.context?.columnLabelFrame(2))
        try click(controller.context?.rowLabelFrame(1))
        XCTAssertEqual(model.current, url("c2"))
    }

    func testClickingALabelWhoseCellIsEmptyDoesNothing() throws {
        press(enter)
        press(down)
        try click(controller.context?.columnLabelFrame(1))
        XCTAssertEqual(model.current, url("a2"))
    }

    func testClickingARowLabelWhoseCellIsEmptyDoesNothing() throws {
        press(enter)
        press(right)
        XCTAssertEqual(model.current, url("b1"))
        try click(controller.context?.rowLabelFrame(1))
        XCTAssertEqual(model.current, url("b1"))
    }

    func testAShortHeaderShowsTheCurrentRowInsideIt() throws {
        let context = ComparisonContextView(comparison: Comparison(variants: [longVariant]))
        context.frame = NSRect(x: 0, y: 0, width: 600, height: ComparisonContextView.columnHeaderHeight + 30)
        context.current = cell(50, 0)
        context.layoutSubtreeIfNeeded()
        let header = CGRect(x: 0, y: ComparisonContextView.columnHeaderHeight, width: ComparisonContextView.rowHeaderWidth, height: 30)
        XCTAssertTrue(header.contains(try XCTUnwrap(context.rowLabelFrame(50))))
    }

    func testClickingTheMapOpensThatCell() throws {
        press(enter)
        let context = try XCTUnwrap(controller.context)
        let rect = ComparisonMapLayout.rect(of: cell(1, 2), columns: 3, rows: 2)
        click(CGPoint(x: context.mapFrame.minX + rect.midX, y: context.mapFrame.minY + rect.midY), in: context)
        XCTAssertEqual(model.current, url("c2"))
    }

    func testClickingAHeaderKeepsTheViewerFocused() throws {
        press(enter)
        try click(controller.context?.columnLabelFrame(2))
        XCTAssertTrue(window.firstResponder is ViewerView)
        press(right)
        XCTAssertEqual(model.current, url("a1"), "wraps from c1 to a1")
    }

    func testClickOverThePhotoStillReachesTheViewer() throws {
        press(enter)
        let content = try XCTUnwrap(window.contentView)
        let centre = CGPoint(x: content.bounds.midX, y: content.bounds.midY)
        XCTAssertTrue(content.hitTest(centre) is ViewerView)
    }

    func testToggleHidesTheContextAndTheViewerFillsTheWindow() throws {
        press(enter)
        let context = try XCTUnwrap(controller.context)
        controller.toggleComparisonContext(nil)
        XCTAssertTrue(context.isHidden)
        XCTAssertEqual(viewer.frame, window.contentView!.bounds)
        XCTAssertEqual(UserDefaults.standard.object(forKey: BrowserWindowController.contextKey) as? Bool, false)
        controller.toggleComparisonContext(nil)
        XCTAssertFalse(context.isHidden)
        XCTAssertEqual(viewer.frame, insetViewerFrame)
    }

    func testToggleWhileInTheGridStaysHidden() throws {
        let context = try XCTUnwrap(controller.context)
        controller.toggleComparisonContext(nil)
        controller.toggleComparisonContext(nil)
        XCTAssertTrue(context.isHidden)
        press(enter)
        XCTAssertFalse(context.isHidden)
    }

    func testOffStaysOffWhenReturningFromTheGrid() throws {
        press(enter)
        controller.toggleComparisonContext(nil)
        press(esc)
        press(esc)
        XCTAssertTrue(window.firstResponder is ViewerView)
        XCTAssertEqual(controller.context?.isHidden, true)
    }

    func testMenuItemReflectsTheSetting() {
        let item = NSMenuItem(title: "", action: #selector(BrowserWindowController.toggleComparisonContext(_:)), keyEquivalent: "")
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
        controller.toggleComparisonContext(nil)
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)
    }

    private func standalone(_ variants: [Variant], current: Comparison.Cell) -> ComparisonContextView {
        let context = ComparisonContextView(comparison: Comparison(variants: variants))
        context.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        context.current = current
        context.layoutSubtreeIfNeeded()
        return context
    }

    private var longVariant: Variant { Variant(label: "a", files: (0..<100).map { URL(fileURLWithPath: "/x/a-\($0).png") }) }

    func testALongComparisonsMapStaysInThePhotoArea() {
        let context = standalone([longVariant], current: cell(0, 0))
        XCTAssertLessThanOrEqual(context.mapFrame.maxY, 400 - ComparisonContextView.mapMargin)
        XCTAssertGreaterThanOrEqual(context.mapFrame.minY, ComparisonContextView.columnHeaderHeight + ComparisonContextView.mapMargin)
    }

    func testManyRowsWindowAroundTheCurrentOne() throws {
        let context = standalone([longVariant], current: cell(50, 0))
        var selected: [Comparison.Cell] = []
        context.onSelect = { selected.append($0) }
        let header = CGRect(x: 0, y: ComparisonContextView.columnHeaderHeight, width: ComparisonContextView.rowHeaderWidth,
                            height: 400 - ComparisonContextView.columnHeaderHeight)
        let shown = (0..<100).compactMap(context.rowLabelFrame)
        XCTAssertFalse(shown.isEmpty)
        XCTAssertLessThan(shown.count, 100)
        XCTAssertTrue(shown.allSatisfy(header.contains), "every shown label inside the row header")
        XCTAssertNil(context.rowLabelFrame(0))
        XCTAssertNotNil(context.rowLabelFrame(50))
        XCTAssertEqual(context.rowLabels.filter { !$0.isHidden }.count, shown.count)
        // The slot above the first shown label is the "more" marker.
        let first = try XCTUnwrap(shown.first)
        let marker = context.convert(CGPoint(x: first.midX, y: first.midY - ComparisonContextView.rowHeight), to: nil)
        context.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: marker, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        XCTAssertTrue(selected.isEmpty)
        let label = context.convert(CGPoint(x: first.midX, y: first.midY), to: nil)
        context.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: label, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        XCTAssertEqual(selected.count, 1, "the label itself does select, so the marker miss is real")
    }

    func testColumnLabelsShareTheWidth() {
        let wide = (0..<12).map { Variant(label: "v\($0)", files: [URL(fileURLWithPath: "/x/v\($0).png")]) }
        let context = standalone(wide, current: cell(0, 0))
        let frames = (0..<12).map(context.columnLabelFrame)
        XCTAssertLessThanOrEqual(frames[11].maxX, 600)
        XCTAssertGreaterThanOrEqual(frames[0].minX, ComparisonContextView.rowHeaderWidth)
        XCTAssertEqual(Set(frames.map(\.width)).count, 1)
    }

    func testEmptyCellIsAPlaceholderInPlace() throws {
        let grid = try XCTUnwrap(window.firstResponder as? ComparisonGridView)
        XCTAssertEqual(grid.cellViews.count, 6)
        XCTAssertNil(grid.cellViews[1 * 3 + 1].url)
        XCTAssertEqual(grid.cellViews[1 * 3 + 2].url, url("c2"))
    }
}
