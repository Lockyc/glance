import AppKit
@testable import glance
import GlanceCore
import UniformTypeIdentifiers
import XCTest

/// The spec's key table, driven with synthetic key events — no focus or window server input needed.
final class KeyHandlingTests: XCTestCase {
    override func setUp() { _ = NSApplication.shared }

    private func key(_ characters: String, _ keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    private var right: NSEvent { key(String(UnicodeScalar(NSRightArrowFunctionKey)!), 124) }
    private var left: NSEvent { key(String(UnicodeScalar(NSLeftArrowFunctionKey)!), 123) }
    private var home: NSEvent { key(String(UnicodeScalar(NSHomeFunctionKey)!), 115) }
    private var end: NSEvent { key(String(UnicodeScalar(NSEndFunctionKey)!), 119) }
    private var esc: NSEvent { key("\u{1B}", 53) }
    private var enter: NSEvent { key("\r", 36) }

    func testViewerKeysMapToCommands() {
        let viewer = ViewerView()
        var commands: [ViewerCommand] = []
        viewer.onCommand = { commands.append($0) }
        for event in [right, left, home, end, key("g", 5), key(" ", 49), key("f", 3), esc] { viewer.keyDown(with: event) }
        XCTAssertEqual(commands, [.next, .previous, .first, .last, .toggleGrid, .toggleGrid, .toggleFullScreen, .exitFullScreen])
    }

    func testWindowNavigatesAndRoundTripsThroughTheGrid() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["a.png", "b.png", "c.png"] {
            writeTestPNG(to: dir.appendingPathComponent(name))
        }
        let model = try FolderModel.load(folder: dir, current: dir.appendingPathComponent("a.png"))
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)")
        let controller = BrowserWindowController(model: model, thumbnails: ThumbnailService(cacheDirectory: cache), startInGrid: false)
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(window.firstResponder is ViewerView)
        window.firstResponder?.keyDown(with: right)
        XCTAssertEqual(model.current?.lastPathComponent, "b.png")
        window.firstResponder?.keyDown(with: end)
        XCTAssertEqual(model.currentIndex, 2)
        window.firstResponder?.keyDown(with: right)
        XCTAssertEqual(model.currentIndex, 0, "wraps")

        window.firstResponder?.keyDown(with: key("g", 5))
        XCTAssertTrue(window.firstResponder is GridCollectionView, "g opens the grid")
        window.firstResponder?.keyDown(with: esc)
        XCTAssertTrue(window.firstResponder is ViewerView, "Esc returns to the viewer")

        window.firstResponder?.keyDown(with: key(" ", 49))
        let grid = try XCTUnwrap(window.firstResponder as? GridCollectionView)
        grid.selectionIndexPaths = [IndexPath(item: 1, section: 0)]
        grid.keyDown(with: enter)
        XCTAssertTrue(window.firstResponder is ViewerView, "Return opens the selection")
        XCTAssertEqual(model.currentIndex, 1)
        controller.close()
    }
}
