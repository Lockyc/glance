import AppKit
@testable import glance
import GlanceCore
import XCTest

/// The thumbnail grid's hover preview, driven with synthetic mouse events.
final class HoverPreviewTests: XCTestCase {
    private var controller: BrowserWindowController!
    private var collection: GridCollectionView!
    private var grid: GridViewController!
    private var preview: HoverPreviewView!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-hover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        writeTestPNG(to: dir.appendingPathComponent("a.png"), width: 64, height: 48, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        try Data("not an image".utf8).write(to: dir.appendingPathComponent("b.png"))
        let model = try FolderModel.load(folder: dir, current: dir.appendingPathComponent("a.png"))
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)")
        controller = BrowserWindowController(model: model, thumbnails: ThumbnailService(cacheDirectory: cache), startInGrid: true)
        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()
        collection = try XCTUnwrap(window.firstResponder as? GridCollectionView)
        grid = try XCTUnwrap(collection.dataSource as? GridViewController)
        preview = try XCTUnwrap(descendants(of: grid.view, HoverPreviewView.self).first)
    }

    override func tearDown() { controller.close() }

    /// The window point at the centre of tile `index`.
    private func tile(_ index: Int) throws -> NSPoint {
        let item = try XCTUnwrap(collection.item(at: IndexPath(item: index, section: 0)))
        return collection.convert(NSPoint(x: item.view.frame.midX, y: item.view.frame.midY), to: nil)
    }

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: controller.window!.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func wait(_ seconds: TimeInterval = 0.6) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    func testHoveringAnImageShowsItsPreview() throws {
        grid.mouseMoved(with: mouse(.mouseMoved, at: try tile(0)))
        wait()
        XCTAssertFalse(preview.isHidden)
    }

    func testAPreviewArmedBeforeAClickNeverShowsOnReturnToTheGrid() throws {
        let point = try tile(0)
        grid.mouseMoved(with: mouse(.mouseMoved, at: point))
        collection.mouseDown(with: mouse(.leftMouseDown, at: point))
        XCTAssertFalse(controller.showingGrid, "the click opens the viewer")
        wait()
        controller.showGrid()
        XCTAssertTrue(preview.isHidden)
    }

    func testAnImageThatFailsToLoadShowsNoPreview() throws {
        grid.mouseMoved(with: mouse(.mouseMoved, at: try tile(1)))
        wait()
        XCTAssertTrue(preview.isHidden)
    }
}
