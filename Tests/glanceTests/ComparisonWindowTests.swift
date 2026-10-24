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

    // MARK: Context (strip + map) in the viewer

    private var viewer: ViewerView { controller.window!.contentView!.subviews.compactMap { $0 as? ViewerView }.first! }

    /// A single click at a point in the context view's coordinates, delivered to whatever the window hit-tests there.
    private func click(_ point: CGPoint, in context: ComparisonContextView) {
        let location = context.convert(point, to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let content = try! XCTUnwrap(window.contentView)
        content.hitTest(content.convert(location, from: nil))?.mouseDown(with: event)
    }

    private func stripClick(column: Int) throws {
        let context = try XCTUnwrap(controller.context)
        let frame = context.stripFrame(column: column)
        click(CGPoint(x: frame.midX, y: frame.midY), in: context)
    }

    func testContextShowsInTheViewerOnly() throws {
        let context = try XCTUnwrap(controller.context)
        XCTAssertTrue(context.isHidden)
        press(enter)
        XCTAssertFalse(context.isHidden)
        XCTAssertEqual(viewer.frame.minY, ComparisonContextView.stripHeight)
        press(esc)
        XCTAssertTrue(context.isHidden)
    }

    func testStripFollowsTheRowAndHighlightsTheCurrentCell() throws {
        press(enter)
        press(down)
        XCTAssertEqual(model.current, url("a2"))
        let strip = try XCTUnwrap(controller.context).stripCells
        XCTAssertEqual(strip.map(\.url), [url("a2"), nil, url("c2")])
        XCTAssertEqual(strip.map(\.isSelected), [true, false, false])
    }

    func testClickingAStripCellOpensIt() throws {
        press(enter)
        try stripClick(column: 2)
        XCTAssertEqual(model.current, url("c1"))
    }

    func testClickingAnEmptyStripCellDoesNothing() throws {
        press(enter)
        press(down)
        try stripClick(column: 1)
        XCTAssertEqual(model.current, url("a2"))
    }

    func testClickingTheMapOpensThatCell() throws {
        press(enter)
        let context = try XCTUnwrap(controller.context)
        let rect = ComparisonMapLayout.rect(of: cell(1, 2), columns: 3, rows: 2)
        click(CGPoint(x: context.mapFrame.minX + rect.midX, y: context.mapFrame.minY + rect.midY), in: context)
        XCTAssertEqual(model.current, url("c2"))
    }

    func testClickingTheStripKeepsTheViewerFocused() throws {
        press(enter)
        try stripClick(column: 2)
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
        XCTAssertEqual(viewer.frame.minY, ComparisonContextView.stripHeight)
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

    func testALongComparisonsMapStaysAboveTheStrip() {
        let long = Comparison(variants: [Variant(label: "a", files: (0..<100).map { URL(fileURLWithPath: "/x/a\($0).png") })])
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)")
        let context = ComparisonContextView(comparison: long, thumbnails: ThumbnailService(decoder: decoder, cacheDirectory: cache))
        context.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        XCTAssertLessThanOrEqual(context.mapFrame.maxY, 400 - ComparisonContextView.stripHeight - ComparisonContextView.mapMargin)
    }

    func testStripCellsShareTheWidth() {
        let wide = Comparison(variants: (0..<12).map { Variant(label: "v\($0)", files: [URL(fileURLWithPath: "/x/v\($0).png")]) })
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)")
        let context = ComparisonContextView(comparison: wide, thumbnails: ThumbnailService(decoder: decoder, cacheDirectory: cache))
        context.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        context.layoutSubtreeIfNeeded()
        let frames = (0..<12).map(context.stripFrame(column:))
        XCTAssertLessThanOrEqual(frames[11].maxX, 600 - 6)
        XCTAssertGreaterThanOrEqual(frames[0].minX, 6)
        XCTAssertEqual(Set(frames.map(\.width)).count, 1)
    }

    func testEmptyCellIsAPlaceholderInPlace() throws {
        let grid = try XCTUnwrap(window.firstResponder as? ComparisonGridView)
        XCTAssertEqual(grid.cellViews.count, 6)
        XCTAssertNil(grid.cellViews[1 * 3 + 1].url)
        XCTAssertEqual(grid.cellViews[1 * 3 + 2].url, url("c2"))
    }
}
