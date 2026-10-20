import AppKit
@testable import glance
import GlanceCore
import UniformTypeIdentifiers
import XCTest

/// A root folder browsed as one oldest-first stream.
final class SubfolderBrowsingTests: XCTestCase {
    private var root: URL!
    private var roots: SubfolderRoots!
    private var delegate: AppDelegate!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-tree-\(UUID().uuidString)").resolvingSymlinksInPath()
        roots = SubfolderRoots(defaults: UserDefaults(suiteName: "glance-tests-\(UUID().uuidString)")!)
        write("2025/03/a.png", day: 0)
        write("2025/03/b.png", day: 1)
        write("2025/04/c.png", day: 25)
        write("d.png", day: 40)
        write("timeline/t.png", day: 2)
        roots.enable(root)
        roots.setExcluded("timeline", true, in: root)
        delegate = AppDelegate(roots: roots)
    }

    override func tearDown() { delegate.controllers.forEach { $0.close() } }

    private func write(_ path: String, day: Int) {
        let url = root.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        writeTestPNG(to: url)
        try! FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_741_564_800 + Double(day) * 86_400)], ofItemAtPath: url.path)
    }

    private func spin(_ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private var controller: BrowserWindowController { delegate.controllers[0] }
    private var names: [String] { controller.model.files.map(\.lastPathComponent) }

    private func key(_ characters: String, _ keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    private var right: NSEvent { key(String(UnicodeScalar(NSRightArrowFunctionKey)!), 124) }

    func testOpeningAFileInsideARootListsTheWholeTreeOldestFirst() {
        delegate.openURL(root.appendingPathComponent("2025/04/c.png"))
        spin { self.names.count == 4 }
        XCTAssertEqual(controller.model.folder.path, root.path)
        XCTAssertEqual(names, ["a.png", "b.png", "c.png", "d.png"])
        XCTAssertEqual(controller.model.current?.lastPathComponent, "c.png")
    }

    func testRightArrowCrossesAMonthInTheViewer() throws {
        delegate.openURL(root.appendingPathComponent("2025/03/b.png"))
        spin { self.names.count == 4 }
        let window = try XCTUnwrap(controller.window)
        window.firstResponder?.keyDown(with: right)
        XCTAssertEqual(controller.model.current?.lastPathComponent, "c.png")
    }

    func testRightArrowCrossesAMonthInTheGrid() throws {
        delegate.openURL(root.appendingPathComponent("2025/03/b.png"))
        spin { self.names.count == 4 }
        controller.showGrid()
        let grid = try XCTUnwrap(controller.window?.firstResponder as? GridCollectionView)
        XCTAssertEqual(grid.selectionIndexPaths, [IndexPath(item: 1, section: 0)])
        grid.keyDown(with: right)
        XCTAssertEqual(grid.selectionIndexPaths, [IndexPath(item: 0, section: 1)])
    }

    func testFlatGridHasNoHeaders() throws {
        delegate.openURL(root.appendingPathComponent("timeline/t.png"))
        controller.showGrid()
        let grid = try XCTUnwrap(controller.window?.firstResponder as? GridCollectionView)
        XCTAssertEqual(grid.numberOfSections, 1)
        XCTAssertEqual((grid.collectionViewLayout as? NSCollectionViewFlowLayout)?.headerReferenceSize.height, 0)
    }

    func testOpeningTheRootLandsOnTheNewest() {
        delegate.openURL(root)
        spin { self.names.count == 4 && self.controller.model.currentIndex == 3 }
        XCTAssertEqual(controller.model.current?.lastPathComponent, "d.png")
    }

    func testOpeningASubfolderLandsOnItsNewest() {
        delegate.openURL(root.appendingPathComponent("2025/03"))
        spin { self.names.count == 4 && self.controller.model.current?.lastPathComponent == "b.png" }
        XCTAssertEqual(controller.model.folder.path, root.path)
        XCTAssertEqual(controller.model.current?.lastPathComponent, "b.png")
    }

    func testFileInAnExcludedFolderOpensThatFolderFlat() {
        delegate.openURL(root.appendingPathComponent("timeline/t.png"))
        XCTAssertEqual(controller.model.folder.path, root.appendingPathComponent("timeline").path)
        XCTAssertEqual(controller.model.scope, .flat)
    }

    func testAFileAddedInASubfolderAppears() {
        delegate.openURL(root.appendingPathComponent("d.png"))
        spin { self.names.count == 4 }
        write("2025/04/e.png", day: 30)
        spin { self.names.count == 5 }
        XCTAssertEqual(names, ["a.png", "b.png", "c.png", "e.png", "d.png"])
    }

    func testAFileAddedDuringTheFirstWalkStillAppears() {
        delegate.openURL(root.appendingPathComponent("d.png"))
        write("2025/04/e.png", day: 30) // before the first background walk has necessarily finished
        spin { self.names.count == 5 }
        XCTAssertEqual(names.count, 5)
    }

    func testTogglingIncludeSubfoldersOffAndOnRescans() {
        delegate.openURL(root.appendingPathComponent("2025/03/a.png"))
        spin { self.names.count == 4 }
        controller.toggleSubfolders(nil)
        spin { self.names == ["d.png"] }
        XCTAssertEqual(names, ["d.png"], "root's own images only")
        XCTAssertFalse(controller.isRoot)
        controller.toggleSubfolders(nil)
        spin { self.names.count == 5 }
        XCTAssertEqual(names, ["a.png", "b.png", "t.png", "c.png", "d.png"], "turning off forgets the root's exclusions")
        XCTAssertTrue(controller.isRoot)
    }

    func testSubfoldersMenuListsTopLevelFoldersCheckedWhenIncluded() {
        delegate.openURL(root.appendingPathComponent("d.png"))
        spin { self.names.count == 4 }
        let menu = NSMenu()
        SubfoldersMenu.shared.populate(menu, for: controller)
        XCTAssertEqual(menu.items.map(\.title), ["2025", "timeline"])
        menu.items.forEach { _ = controller.validateMenuItem($0) }
        XCTAssertEqual(menu.items.map(\.state), [.on, .off])
    }

    func testANewTopLevelFolderJoinsTheSubfoldersMenu() {
        delegate.openURL(root.appendingPathComponent("d.png"))
        spin { self.names.count == 4 }
        write("2026/e.png", day: 50)
        spin { self.names.count == 5 }
        spin { self.controller.subfolders().count == 3 }
        XCTAssertEqual(controller.subfolders(), ["2025", "2026", "timeline"])
    }

    func testSubfoldersMenuExplainsItselfWhenOff() {
        delegate.openURL(root.appendingPathComponent("timeline/t.png"))
        let menu = NSMenu()
        SubfoldersMenu.shared.populate(menu, for: controller)
        XCTAssertEqual(menu.items.count, 1)
        XCTAssertFalse(menu.items[0].isEnabled)
    }

    func testExcludingASubfolderFromTheMenuRescans() {
        delegate.openURL(root.appendingPathComponent("d.png"))
        spin { self.names.count == 4 }
        XCTAssertEqual(controller.subfolders(), ["2025", "timeline"])
        let item = NSMenuItem(title: "2025", action: nil, keyEquivalent: "")
        item.representedObject = "2025"
        controller.toggleExcludedSubfolder(item)
        spin { self.names == ["d.png"] }
        XCTAssertEqual(roots.root(at: root)?.excluded, ["2025", "timeline"])
    }
}
