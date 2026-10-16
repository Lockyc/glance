@testable import GlanceCore
import XCTest

final class SubfolderRootsTests: XCTestCase {
    private func store() -> SubfolderRoots {
        SubfolderRoots(defaults: UserDefaults(suiteName: "glance-tests-\(UUID().uuidString)")!)
    }

    private func dir(_ path: String, in base: URL) -> URL {
        let url = base.appendingPathComponent(path, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testCoversFilesAndFoldersAtAnyDepthUnderARoot() {
        let base = Fixtures.tempDir().resolvingSymlinksInPath()
        let roots = store()
        roots.enable(base)
        let deep = dir("2025/03-March", in: base)
        XCTAssertEqual(roots.root(covering: deep.appendingPathComponent("a.png"))?.path, base.path)
        XCTAssertEqual(roots.root(covering: deep)?.path, base.path)
        XCTAssertEqual(roots.root(covering: base)?.path, base.path)
        XCTAssertNil(roots.root(covering: base.deletingLastPathComponent().appendingPathComponent("other.png")))
    }

    func testSiblingWithSharedPrefixIsNotCovered() {
        let base = Fixtures.tempDir().resolvingSymlinksInPath()
        let roots = store()
        roots.enable(dir("Shots", in: base))
        XCTAssertNil(roots.root(covering: dir("Shots2", in: base).appendingPathComponent("a.png")))
    }

    func testExcludedFolderAndEverythingUnderItIsNotCovered() {
        let base = Fixtures.tempDir().resolvingSymlinksInPath()
        let roots = store()
        roots.enable(base)
        roots.setExcluded("timeline", true, in: base)
        let day = dir("timeline/2026-07-07", in: base)
        XCTAssertNil(roots.root(covering: day.appendingPathComponent("a.png")))
        XCTAssertNil(roots.root(covering: base.appendingPathComponent("timeline")))
        XCTAssertNotNil(roots.root(covering: dir("timelines", in: base).appendingPathComponent("a.png")), "prefix of a name is not a match")
    }

    func testDeepestRootWinsForAnExcludedFolderThatIsItsOwnRoot() {
        let base = Fixtures.tempDir().resolvingSymlinksInPath()
        let roots = store()
        roots.enable(base)
        roots.setExcluded("timeline", true, in: base)
        let timeline = dir("timeline", in: base)
        roots.enable(timeline)
        XCTAssertEqual(roots.root(covering: timeline.appendingPathComponent("x/a.png"))?.path, timeline.path)
    }

    func testPrivateVarAndVarAreTheSameRoot() {
        let roots = store()
        let real = Fixtures.tempDir() // /var/folders/…, a symlink to /private/var/folders/…
        roots.enable(URL(fileURLWithPath: "/private" + real.resolvingSymlinksInPath().path))
        XCTAssertNotNil(roots.root(at: real))
        XCTAssertNotNil(roots.root(covering: real.resolvingSymlinksInPath().appendingPathComponent("a.png")))
    }

    func testPersistsAcrossInstancesAndNotifies() {
        let suite = "glance-tests-\(UUID().uuidString)"
        let base = Fixtures.tempDir().resolvingSymlinksInPath()
        let first = SubfolderRoots(defaults: UserDefaults(suiteName: suite)!)
        let notified = expectation(forNotification: SubfolderRoots.didChange, object: first)
        notified.expectedFulfillmentCount = 2
        first.enable(base)
        first.setExcluded("timeline", true, in: base)
        wait(for: [notified], timeout: 1)
        let second = SubfolderRoots(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(second.roots, [SubfolderRoots.Root(path: base.path, excluded: ["timeline"])])
    }

    func testDisableRemovesAndEnableIsIdempotent() {
        let base = Fixtures.tempDir().resolvingSymlinksInPath()
        let roots = store()
        roots.enable(base)
        roots.enable(base)
        XCTAssertEqual(roots.roots.count, 1)
        roots.disable(base)
        XCTAssertTrue(roots.roots.isEmpty)
    }

    func testReincludingAFolderRemovesTheExclusion() {
        let base = Fixtures.tempDir().resolvingSymlinksInPath()
        let roots = store()
        roots.enable(base)
        roots.setExcluded("a/b", true, in: base)
        roots.setExcluded("a/b", false, in: base)
        XCTAssertEqual(roots.root(at: base)?.excluded, [])
    }

    func testRelativePath() {
        let base = URL(fileURLWithPath: "/x/Shots")
        XCTAssertEqual(SubfolderRoots.relativePath(of: URL(fileURLWithPath: "/x/Shots"), in: base), "")
        XCTAssertEqual(SubfolderRoots.relativePath(of: URL(fileURLWithPath: "/x/Shots/2025/03"), in: base), "2025/03")
        XCTAssertNil(SubfolderRoots.relativePath(of: URL(fileURLWithPath: "/x/Shots2/a"), in: base))
        XCTAssertNil(SubfolderRoots.relativePath(of: URL(fileURLWithPath: "/x"), in: base))
    }
}
