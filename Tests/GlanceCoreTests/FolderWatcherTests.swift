import GlanceCore
import XCTest

final class FolderWatcherTests: XCTestCase {
    func testReportsAddedFile() throws {
        let dir = Fixtures.tempDir()
        let fired = expectation(description: "change")
        let watcher = try XCTUnwrap(FolderWatcher(folder: dir) { fired.fulfill() })
        Fixtures.touch(["new.jpg"], in: dir)
        wait(for: [fired], timeout: 2)
        _ = watcher
    }

    func testCoalescesABurstIntoOneCallback() throws {
        let dir = Fixtures.tempDir()
        var count = 0
        let watcher = try XCTUnwrap(FolderWatcher(folder: dir, debounce: 0.2) { count += 1 })
        Fixtures.touch((0..<20).map { "f\($0).jpg" }, in: dir)
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(count, 1)
        _ = watcher
    }

    func testReportsRemovedFile() throws {
        let dir = Fixtures.tempDir()
        Fixtures.touch(["gone.jpg"], in: dir)
        let fired = expectation(description: "change")
        let watcher = try XCTUnwrap(FolderWatcher(folder: dir) { fired.fulfill() })
        try FileManager.default.removeItem(at: dir.appendingPathComponent("gone.jpg"))
        wait(for: [fired], timeout: 2)
        _ = watcher
    }

    func testMissingFolderFailsToInit() {
        XCTAssertNil(FolderWatcher(folder: URL(fileURLWithPath: "/nonexistent-\(UUID())")) {})
    }
}
