import AppKit
@testable import glance
import GlanceCore
import XCTest

/// ⌘R shows the image in view, or the grid's selection, in Finder.
final class ShowInFinderTests: XCTestCase {
    override func setUp() { _ = NSApplication.shared }

    private func controller(_ names: [String]) throws -> BrowserWindowController {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-reveal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names { writeTestPNG(to: dir.appendingPathComponent(name)) }
        let model = try FolderModel.load(folder: dir, current: dir.appendingPathComponent(names[1]))
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)")
        return BrowserWindowController(model: model, thumbnails: ThumbnailService(cacheDirectory: cache), startInGrid: false)
    }

    private var menuItem: NSMenuItem {
        MainMenu.make(updater: nil).items.compactMap(\.submenu).first { $0.title == "File" }!
            .items.first { $0.action == #selector(BrowserWindowController.showInFinder(_:)) }!
    }

    func testTheMenuItemIsCommandR() {
        XCTAssertEqual(menuItem.title, "Show in Finder")
        XCTAssertEqual(menuItem.keyEquivalent, "r")
        XCTAssertEqual(menuItem.keyEquivalentModifierMask, .command)
    }

    func testTheViewerRevealsTheImageInView() throws {
        let controller = try controller(["a.png", "b.png", "c.png"])
        var revealed: [URL] = []
        controller.finder = { revealed = $0 }
        XCTAssertTrue(controller.validateMenuItem(menuItem))
        controller.showInFinder(nil)
        XCTAssertEqual(revealed.map(\.lastPathComponent), ["b.png"])
    }

    func testTheGridRevealsItsSelection() throws {
        let controller = try controller(["a.png", "b.png", "c.png"])
        var revealed: [URL] = []
        controller.finder = { revealed = $0 }
        controller.showGrid()
        let grid = try XCTUnwrap(controller.window?.firstResponder as? GridCollectionView)
        grid.selectionIndexPaths = [IndexPath(item: 2, section: 0), IndexPath(item: 0, section: 0)]
        controller.showInFinder(nil)
        XCTAssertEqual(revealed.map(\.lastPathComponent), ["a.png", "c.png"])
    }

    func testAnEmptyGridSelectionDisablesItWithItsReason() throws {
        let controller = try controller(["a.png", "b.png"])
        controller.finder = { _ in XCTFail("refused") }
        controller.showGrid()
        let grid = try XCTUnwrap(controller.window?.firstResponder as? GridCollectionView)
        grid.selectionIndexPaths = []
        let item = menuItem
        XCTAssertFalse(controller.validateMenuItem(item))
        XCTAssertEqual(item.toolTip, "No image selected")
        controller.showInFinder(nil)
    }
}
