import AppKit
@testable import glance
import GlanceCore
import XCTest

/// Stands in for the hover delay: an armed preview waits for `fire()`, and a disarmed one never runs.
final class ManualDelay {
    private var armed: [Int: () -> Void] = [:]
    private var next = 0
    var isArmed: Bool { !armed.isEmpty }

    func arm(_ fire: @escaping () -> Void) -> () -> Void {
        let id = next
        next += 1
        armed[id] = fire
        return { [weak self] in self?.armed[id] = nil }
    }

    func fire() {
        let pending = armed.values
        armed = [:]
        pending.forEach { $0() }
    }
}

/// The thumbnail grid's hover preview, driven with synthetic mouse events and a delay the test fires.
final class HoverPreviewTests: XCTestCase {
    private var controller: BrowserWindowController!
    private var collection: GridCollectionView!
    private var grid: GridViewController!
    private var preview: HoverPreviewView!
    private var delay: ManualDelay!
    private var dir: URL!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-hover-\(UUID().uuidString)")
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
        delay = ManualDelay()
        grid.previewer.arm = delay.arm
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

    private func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Fires the hover delay, then runs the loop until the preview has its image.
    private func fireAndAwaitPreview() {
        delay.fire()
        let deadline = Date().addingTimeInterval(5)
        while preview.isHidden, Date() < deadline { wait(0.01) }
    }

    func testHoveringAnImageShowsItsPreviewOnlyAfterTheDelay() throws {
        grid.mouseMoved(with: mouse(.mouseMoved, at: try tile(0)))
        XCTAssertTrue(delay.isArmed)
        XCTAssertTrue(preview.isHidden, "shown before the delay")
        fireAndAwaitPreview()
        XCTAssertFalse(preview.isHidden)
    }

    func testAPreviewArmedBeforeAClickNeverShowsOnReturnToTheGrid() throws {
        let point = try tile(0)
        grid.mouseMoved(with: mouse(.mouseMoved, at: point))
        collection.mouseDown(with: mouse(.leftMouseDown, at: point))
        XCTAssertFalse(controller.showingGrid, "the click opens the viewer")
        XCTAssertFalse(delay.isArmed, "the click left the hover delay armed")
        delay.fire()
        controller.showGrid()
        XCTAssertTrue(preview.isHidden)
    }

    func testAnOpenPreviewRedrawsAReSavedFileInItsNewShape() throws {
        grid.mouseMoved(with: mouse(.mouseMoved, at: try tile(0)))
        fireAndAwaitPreview()
        XCTAssertFalse(preview.isHidden)
        let before = try XCTUnwrap(preview.image)
        XCTAssertGreaterThan(preview.frame.width, preview.frame.height)

        writeTestPNG(to: dir.appendingPathComponent("a.png"), width: 48, height: 64, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let deadline = Date().addingTimeInterval(3)
        while preview.image === before, Date() < deadline { wait(0.02) }
        XCTAssertFalse(preview.image === before, "the open preview kept the old image")
        XCTAssertFalse(preview.isHidden)
        XCTAssertLessThan(preview.frame.width, preview.frame.height, "the preview kept the old shape")
    }

    /// A negative outcome has nothing to await, so this one runs the loop long enough for the failed decode.
    func testAnImageThatFailsToLoadShowsNoPreview() throws {
        grid.mouseMoved(with: mouse(.mouseMoved, at: try tile(1)))
        delay.fire()
        wait(0.3)
        XCTAssertTrue(preview.isHidden)
    }
}
