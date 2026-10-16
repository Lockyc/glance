import GlanceCore
import XCTest

final class TreeWatcherTests: XCTestCase {
    private func paths(_ change: TreeWatcher.Change?) -> Set<String>? {
        guard case .directories(let dirs)? = change else { return nil }
        return Set(dirs.map(\.path))
    }

    /// FSEvents still delivers events from just before a stream starts (here, the fixture's own
    /// folder creation), so tests that count events let those drain first.
    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }

    func testReportsTheFolderAFileWasAddedTo() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("sub/x.png", in: root, created: Fixtures.day(0))
        settle()
        let fired = expectation(description: "change")
        var change: TreeWatcher.Change?
        let watcher = try XCTUnwrap(TreeWatcher(folder: root, recursive: true) { change = $0; fired.fulfill() })
        Fixtures.touch(["new.png"], in: root.appendingPathComponent("sub"))
        wait(for: [fired], timeout: 3)
        XCTAssertEqual(paths(change), [root.appendingPathComponent("sub").resolvingSymlinksInPath().path])
        _ = watcher
    }

    func testFlatWatcherIgnoresSubfolders() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("sub/x.png", in: root, created: Fixtures.day(0))
        settle()
        var count = 0
        let watcher = try XCTUnwrap(TreeWatcher(folder: root, recursive: false) { _ in count += 1 })
        Fixtures.touch(["new.png"], in: root.appendingPathComponent("sub"))
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        XCTAssertEqual(count, 0)
        _ = watcher
    }

    func testFlatWatcherReportsItsOwnFolder() throws {
        let root = Fixtures.tempDir()
        let fired = expectation(description: "change")
        let watcher = try XCTUnwrap(TreeWatcher(folder: root, recursive: false) { _ in fired.fulfill() })
        Fixtures.touch(["new.png"], in: root)
        wait(for: [fired], timeout: 3)
        _ = watcher
    }

    func testCoalescesABurstIntoOneCallback() throws {
        let root = Fixtures.tempDir()
        var changes: [TreeWatcher.Change] = []
        let watcher = try XCTUnwrap(TreeWatcher(folder: root, recursive: true, debounce: 0.3) { changes.append($0) })
        Fixtures.touch((0..<20).map { "f\($0).png" }, in: root)
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        XCTAssertEqual(changes.count, 1)
        _ = watcher
    }

    func testMissingFolderFailsToInit() {
        XCTAssertNil(TreeWatcher(folder: URL(fileURLWithPath: "/nonexistent-\(UUID())"), recursive: true) { _ in })
    }

    func testMergeUnionsDirectoriesAndEverythingAbsorbs() {
        let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/b")
        XCTAssertEqual(TreeWatcher.Change.directories([a]).merged(with: .directories([b])), .directories([a, b]))
        XCTAssertEqual(TreeWatcher.Change.directories([a]).merged(with: .everything), .everything)
        XCTAssertEqual(TreeWatcher.Change.everything.merged(with: .directories([b])), .everything)
    }
}
