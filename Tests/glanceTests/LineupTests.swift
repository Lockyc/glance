import AppKit
@testable import glance
import GlanceCore
import XCTest

/// A lineup: thirteen one-file variants `a`…`m`, wrapped into rows under their own labels.
final class LineupTests: XCTestCase {
    private var dir: URL!
    private var model: FolderModel!
    private var controller: BrowserWindowController!
    private var window: NSWindow!
    private let labels = (0..<13).map { String(UnicodeScalar(UInt8(97 + $0))) }

    override func setUpWithError() throws {
        _ = NSApplication.shared
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-lineup-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let comparison = Comparison(variants: labels.map { label in
            let url = dir.appendingPathComponent("\(label).png")
            writeTestPNG(to: url)
            return Variant(label: label, files: [url])
        })
        model = FolderModel(folder: dir, files: comparison.files.map(FolderModel.canonical), current: nil, scope: .fixed)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)")
        controller = BrowserWindowController(model: model, thumbnails: ThumbnailService(cacheDirectory: cache),
                                             startInGrid: true, comparison: comparison)
        window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    override func tearDown() { controller.close() }

    private func key(_ scalar: Int, _ keyCode: UInt16) -> NSEvent {
        let characters = String(UnicodeScalar(scalar)!)
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    private var grid: ComparisonGridView { get throws { try XCTUnwrap(window.firstResponder as? ComparisonGridView) } }

    /// Cells sharing the first cell's top edge.
    private func perRow(_ grid: ComparisonGridView) -> Int {
        grid.cellViews.filter { $0.frame.minY == grid.cellViews[0].frame.minY }.count
    }

    func testWrapsIntoRowsOfLabelledCellsWithNoHeader() throws {
        let grid = try grid
        let across = perRow(grid)
        XCTAssertGreaterThan(across, 1)
        XCTAssertLessThan(across, labels.count, "wraps instead of one column per variant")
        XCTAssertEqual(grid.cellLabels.map(\.stringValue), labels)
        for (cell, label) in zip(grid.cellViews, grid.cellLabels) {
            XCTAssertEqual(label.frame.minX, cell.frame.minX)
            XCTAssertLessThan(label.frame.maxY, cell.frame.minY, "the label sits above its cell")
        }
        XCTAssertLessThanOrEqual(grid.frame.width, window.contentView!.bounds.width, "no sideways scroll")
    }

    func testArrowsMoveInReadingOrderAndByRow() throws {
        let grid = try grid
        let across = perRow(grid)
        grid.keyDown(with: key(NSDownArrowFunctionKey, 125))
        XCTAssertEqual(grid.selection, Comparison.Cell(row: 0, column: across))
        grid.keyDown(with: key(NSLeftArrowFunctionKey, 123))
        XCTAssertEqual(grid.selection, Comparison.Cell(row: 0, column: across - 1), "← runs back onto the row above")
        grid.keyDown(with: key(NSRightArrowFunctionKey, 124))
        grid.keyDown(with: key(NSUpArrowFunctionKey, 126))
        XCTAssertEqual(grid.selection, Comparison.Cell(row: 0, column: 0))
    }

    func testReturnOpensThePickedCandidate() throws {
        let grid = try grid
        grid.keyDown(with: key(NSDownArrowFunctionKey, 125))
        grid.keyDown(with: key(13, 36))
        XCTAssertTrue(window.firstResponder is ViewerView)
        XCTAssertEqual(model.current?.lastPathComponent, "\(labels[perRow(grid)]).png")
    }
}
