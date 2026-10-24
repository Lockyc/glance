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

    override func tearDown() { controller.close() }

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

    func testEmptyCellIsAPlaceholderInPlace() throws {
        let grid = try XCTUnwrap(window.firstResponder as? ComparisonGridView)
        XCTAssertEqual(grid.cellViews.count, 6)
        XCTAssertNil(grid.cellViews[1 * 3 + 1].url)
        XCTAssertEqual(grid.cellViews[1 * 3 + 2].url, url("c2"))
    }
}
