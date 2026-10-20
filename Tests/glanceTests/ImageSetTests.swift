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
        delegate.ordersWindowsFront = false
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

    private func open(_ request: LaunchRequest) { delegate.application(NSApplication.shared, open: [request.url]) }

    func testSetURLOpensANewFixedWindowOnExactlyThoseFiles() {
        let files = [url("c.png"), url("a.png")]
        open(.set(files))
        XCTAssertEqual(delegate.controllers.count, 1)
        XCTAssertEqual(delegate.controllers[0].model.scope, .fixed)
        XCTAssertEqual(delegate.controllers[0].model.files, files)
        open(.set(files))
        XCTAssertEqual(delegate.controllers.count, 2)
    }

    func testComparisonURLOpensANewWindowInTheComparisonGrid() {
        let request = LaunchRequest.comparison([Variant(label: "a", files: [url("a.png")]),
                                                Variant(label: "b", files: [url("b.png")])])
        open(request)
        open(request)
        XCTAssertEqual(delegate.controllers.count, 2)
        XCTAssertTrue(delegate.controllers.allSatisfy { $0.showingGrid && $0.model.scope == .fixed })
        XCTAssertEqual(delegate.controllers[0].model.files, [url("a.png"), url("b.png")])
    }

    func testFolderURLOpensAFolderWindowAndASecondOpenReusesIt() {
        open(.folder(dir))
        XCTAssertEqual(delegate.controllers.count, 1)
        XCTAssertNotEqual(delegate.controllers[0].model.scope, .fixed)
        open(.folder(dir))
        XCTAssertEqual(delegate.controllers.count, 1)
    }

    func testMalformedURLOpensNothing() {
        delegate.application(NSApplication.shared, open: [URL(string: "glance://open?r=garbage")!])
        XCTAssertTrue(delegate.controllers.isEmpty)
    }
}
