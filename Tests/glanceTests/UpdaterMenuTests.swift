import AppKit
import Sparkle
import XCTest

@testable import glance

final class UpdaterMenuTests: XCTestCase {
    override func setUp() {
        _ = NSApplication.shared  // MainMenu.make sets NSApp.windowsMenu
    }

    private func checkItem(in menu: NSMenu) -> NSMenuItem? {
        menu.items.first?.submenu?.items.first { $0.title == "Check for Updates…" }
    }

    func testAppMenuOffersCheckForUpdatesWithoutAnUpdater() throws {
        let item = try XCTUnwrap(checkItem(in: MainMenu.make(updater: nil)))
        XCTAssertNil(item.action, "with no updater the item stays visible but inert")
    }

    func testCheckForUpdatesTargetsTheUpdater() throws {
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let item = try XCTUnwrap(checkItem(in: MainMenu.make(updater: updater)))
        XCTAssertTrue(item.target === updater)
        XCTAssertEqual(item.action, #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
    }

    func testNoUpdaterOutsideABundleWithAFeed() {
        XCTAssertNil(Updater.make(bundle: Bundle(for: Self.self)))
    }
}
