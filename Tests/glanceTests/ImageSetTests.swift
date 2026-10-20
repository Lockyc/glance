import AppKit
@testable import glance
import GlanceCore
import XCTest

/// A window on an explicit file list: never scanned, never watched.
final class ImageSetTests: XCTestCase {
    private var dir: URL!
    private var delegate: AppDelegate!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-set-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["a.png", "b.png", "c.png"] { writeTestPNG(to: dir.appendingPathComponent(name)) }
        delegate = AppDelegate(roots: SubfolderRoots(defaults: UserDefaults(suiteName: "glance-tests-\(UUID().uuidString)")!))
    }

    override func tearDown() { delegate.controllers.forEach { $0.close() } }

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }

    func testSetWindowShowsOnlyTheListedFilesAndNeverRescans() throws {
        let files = [url("c.png"), url("a.png")]
        let model = FolderModel(folder: dir, files: files, current: nil, scope: .fixed)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)")
        let controller = BrowserWindowController(model: model, thumbnails: ThumbnailService(cacheDirectory: cache), startInGrid: false)
        defer { controller.close() }

        spin(0.5)
        XCTAssertEqual(model.files, files)
        writeTestPNG(to: url("d.png"))
        spin(1)
        XCTAssertEqual(model.files, files)

        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        controller.window?.firstResponder?.keyDown(with: NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: right, charactersIgnoringModifiers: right, isARepeat: false, keyCode: 124)!)
        XCTAssertEqual(model.current, url("a.png"))

        XCTAssertFalse(controller.isRoot)
        let item = NSMenuItem(title: "", action: #selector(BrowserWindowController.toggleSubfolders(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(item))
    }

    func testOpenSetAlwaysMakesANewWindowAndFolderOpensSkipIt() {
        delegate.openSet([url("a.png")])
        delegate.openSet([url("a.png")])
        XCTAssertEqual(delegate.controllers.count, 2)
        delegate.openURL(dir)
        XCTAssertEqual(delegate.controllers.count, 3)
    }
}
