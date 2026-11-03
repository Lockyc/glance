import AppKit
@testable import glance
import GlanceCore
import XCTest

/// The image commands — Browse Folder, Show in Finder, Edit in Excerpt — in the File menu and the right-click menu.
final class ImageMenuTests: XCTestCase {
    override func setUp() { _ = NSApplication.shared }

    private func folder(_ names: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-menu-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names { writeTestPNG(to: dir.appendingPathComponent(name)) }
        return dir
    }

    private var thumbnails: ThumbnailService {
        ThumbnailService(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)"))
    }

    private func controller(_ names: [String]) throws -> BrowserWindowController {
        let dir = try folder(names)
        let model = try FolderModel.load(folder: dir, current: dir.appendingPathComponent(names[1]))
        return BrowserWindowController(model: model, thumbnails: thumbnails, startInGrid: false)
    }

    /// `before/table.png` and `after/table.png`, compared side by side, as `glance --variant` opens them.
    private func comparison() throws -> (BrowserWindowController, URL, URL) {
        let before = try folder(["table.png"]).appendingPathComponent("table.png")
        let after = try folder(["table.png"]).appendingPathComponent("table.png")
        let comparison = Comparison(variants: [Variant(label: "before", files: [before]), Variant(label: "after", files: [after])])
        let model = FolderModel(folder: before.deletingLastPathComponent(), files: comparison.files.map(FolderModel.canonical),
                                current: nil, scope: .fixed)
        let controller = BrowserWindowController(model: model, thumbnails: thumbnails, startInGrid: true, comparison: comparison)
        controller.window?.layoutIfNeeded()
        return (controller, before, after)
    }

    private func item(_ action: Selector, in menu: NSMenu) -> NSMenuItem { menu.items.first { $0.action == action }! }

    private var fileMenu: NSMenu { MainMenu.make(updater: nil).items.compactMap(\.submenu).first { $0.title == "File" }! }

    private func rightClick(_ view: NSView, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: .rightMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                           windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    func testTheFileMenuAndTheRightClickMenuCarryTheSameCommands() {
        let actions = [#selector(BrowserWindowController.browseFolder(_:)), #selector(BrowserWindowController.showInFinder(_:)),
                       #selector(BrowserWindowController.editInExcerpt(_:))]
        XCTAssertEqual(MainMenu.contextMenu().items.compactMap(\.action), actions)
        let file = fileMenu
        XCTAssertEqual(item(actions[0], in: file).keyEquivalent, String(UnicodeScalar(NSUpArrowFunctionKey)!))
        XCTAssertEqual(item(actions[1], in: file).keyEquivalent, "r")
        XCTAssertEqual(item(actions[2], in: file).keyEquivalent, "e")
        let click = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        XCTAssertEqual(ViewerView().menu(for: click)?.items.compactMap(\.action), actions)
    }

    func testShowInFinderRevealsTheImageInView() throws {
        let controller = try controller(["a.png", "b.png", "c.png"])
        var revealed: [URL] = []
        controller.finder = { revealed = $0 }
        XCTAssertTrue(controller.validateMenuItem(item(#selector(BrowserWindowController.showInFinder(_:)), in: fileMenu)))
        controller.showInFinder(nil)
        XCTAssertEqual(revealed.map(\.lastPathComponent), ["b.png"])
    }

    func testShowInFinderRevealsTheGridSelection() throws {
        let controller = try controller(["a.png", "b.png", "c.png"])
        var revealed: [URL] = []
        controller.finder = { revealed = $0 }
        controller.showGrid()
        let grid = try XCTUnwrap(controller.window?.firstResponder as? GridCollectionView)
        grid.selectionIndexPaths = [IndexPath(item: 2, section: 0), IndexPath(item: 0, section: 0)]
        controller.showInFinder(nil)
        XCTAssertEqual(revealed.map(\.lastPathComponent), ["a.png", "c.png"])
    }

    func testAnEmptyGridSelectionDisablesShowInFinderWithItsReason() throws {
        let controller = try controller(["a.png", "b.png"])
        controller.finder = { _ in XCTFail("refused") }
        controller.showGrid()
        let grid = try XCTUnwrap(controller.window?.firstResponder as? GridCollectionView)
        grid.selectionIndexPaths = []
        let item = item(#selector(BrowserWindowController.showInFinder(_:)), in: fileMenu)
        XCTAssertFalse(controller.validateMenuItem(item))
        XCTAssertEqual(item.toolTip, "No image selected")
        controller.showInFinder(nil)
    }

    func testRightClickingATileOutsideTheSelectionSelectsJustIt() throws {
        let controller = try controller(["a.png", "b.png", "c.png"])
        controller.showGrid()
        controller.window?.layoutIfNeeded()
        let grid = try XCTUnwrap(controller.window?.firstResponder as? GridCollectionView)
        grid.selectionIndexPaths = [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)]
        let third = try XCTUnwrap(grid.layoutAttributesForItem(at: IndexPath(item: 2, section: 0))).frame
        XCTAssertNotNil(grid.menu(for: rightClick(grid, at: NSPoint(x: third.midX, y: third.midY))))
        XCTAssertEqual(grid.selectionIndexPaths, [IndexPath(item: 2, section: 0)])

        grid.selectionIndexPaths = [IndexPath(item: 0, section: 0), IndexPath(item: 2, section: 0)]
        _ = grid.menu(for: rightClick(grid, at: NSPoint(x: third.midX, y: third.midY)))
        XCTAssertEqual(grid.selectionIndexPaths, [IndexPath(item: 0, section: 0), IndexPath(item: 2, section: 0)])
    }

    func testAComparisonBrowsesTheRightClickedImagesFolder() throws {
        let (controller, before, after) = try comparison()
        var browsed: [URL] = []
        controller.browse = { browsed.append($0) }
        let grid = try XCTUnwrap(controller.window?.firstResponder as? ComparisonGridView)
        let cell = grid.cellViews[1].frame
        let menu = try XCTUnwrap(grid.menu(for: rightClick(grid, at: NSPoint(x: cell.midX, y: cell.midY))))

        let browse = item(#selector(BrowserWindowController.browseFolder(_:)), in: menu)
        XCTAssertTrue(controller.validateMenuItem(browse))
        XCTAssertEqual(browse.title, "Browse “\(after.deletingLastPathComponent().lastPathComponent)”")
        controller.browseFolder(nil)
        XCTAssertEqual(browsed, [after])
        _ = before
    }

    func testAnOrdinaryWindowAlreadyBrowsesItsFolder() throws {
        let controller = try controller(["a.png", "b.png"])
        controller.browse = { _ in XCTFail("refused") }
        let item = item(#selector(BrowserWindowController.browseFolder(_:)), in: fileMenu)
        XCTAssertFalse(controller.validateMenuItem(item))
        XCTAssertEqual(item.toolTip, "Already browsing “\(controller.model.folder.lastPathComponent)”")
        controller.browseFolder(nil)
    }
}
