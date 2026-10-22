import AppKit
@testable import glance
import GlanceCore
import XCTest

/// E hands the image in view, or the grid's selection, to Excerpt.
final class EditInExcerptTests: XCTestCase {
    override func setUp() { _ = NSApplication.shared }

    private func key(_ characters: String, _ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    private func controller(_ names: [String]) throws -> (BrowserWindowController, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-edit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names { writeTestPNG(to: dir.appendingPathComponent(name)) }
        let model = try FolderModel.load(folder: dir, current: dir.appendingPathComponent(names[1]))
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)")
        let controller = BrowserWindowController(model: model, thumbnails: ThumbnailService(cacheDirectory: cache), startInGrid: false)
        return (controller, dir)
    }

    func testEIsTheEditCommandInTheViewerAndTheGrids() {
        let viewer = ViewerView()
        var commands: [ViewerCommand] = []
        viewer.onCommand = { commands.append($0) }
        viewer.keyDown(with: key("e", 14))
        XCTAssertEqual(commands, [.editInExcerpt])
        XCTAssertEqual(GridKey.from(key("e", 14)), .editInExcerpt)
        XCTAssertNil(GridKey.from(key("e", 14, .command)))
    }

    func testTheViewerSendsTheImageInView() throws {
        let (controller, dir) = try controller(["a.png", "b.png", "c.png"])
        var sent: [URL] = []
        controller.excerpt = .init(installed: { true }, open: { sent = $0 })
        controller.window?.firstResponder?.keyDown(with: key("e", 14))
        XCTAssertEqual(sent.map(\.lastPathComponent), ["b.png"])
        _ = dir
    }

    func testTheGridSendsItsSelectionInOrder() throws {
        let (controller, _) = try controller(["a.png", "b.png", "c.png"])
        var sent: [URL] = []
        controller.excerpt = .init(installed: { true }, open: { sent = $0 })
        controller.showGrid()
        let grid = try XCTUnwrap(controller.window?.firstResponder as? GridCollectionView)
        XCTAssertTrue(grid.allowsMultipleSelection)
        grid.selectionIndexPaths = [IndexPath(item: 2, section: 0), IndexPath(item: 0, section: 0)]
        grid.keyDown(with: key("e", 14))
        XCTAssertEqual(sent.map(\.lastPathComponent), ["a.png", "c.png"])
    }

    func testTheMenuItemIsDisabledWithItsReason() throws {
        let (controller, _) = try controller(["a.png", "b.png"])
        controller.excerpt = .init(installed: { false }, open: { _ in XCTFail("refused") })
        let item = NSMenuItem(title: "Edit in Excerpt", action: #selector(BrowserWindowController.editInExcerpt(_:)), keyEquivalent: "e")
        XCTAssertFalse(controller.validateMenuItem(item))
        XCTAssertEqual(item.toolTip, "Excerpt isn't installed")
        controller.editInExcerpt(nil)
    }
}
