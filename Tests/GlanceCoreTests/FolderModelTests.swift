@testable import GlanceCore
import XCTest

final class FolderModelTests: XCTestCase {
    private func names(_ model: FolderModel) -> [String] { model.files.map(\.lastPathComponent) }

    private func model(_ files: [String], current: String?) throws -> FolderModel {
        let dir = Fixtures.tempDir()
        Fixtures.touch(files, in: dir)
        return try FolderModel.load(folder: dir, current: current.map { dir.appendingPathComponent($0) })
    }

    func testScanFiltersHiddenAppleDoubleAndNonImages() throws {
        let dir = Fixtures.tempDir()
        Fixtures.touch(["img10.jpg", "img2.JPG", "notes.txt", "doc.pdf", ".hidden.jpg", "._img2.JPG", "vector.svg", "raw.cr3"], in: dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub.jpg"), withIntermediateDirectories: false)
        XCTAssertEqual(try FolderModel.scan(dir).map(\.lastPathComponent), ["img2.JPG", "img10.jpg", "raw.cr3", "vector.svg"])
    }

    func testLoadStartsAtGivenFile() throws {
        let m = try model(["a.jpg", "b.jpg", "c.jpg"], current: "b.jpg")
        XCTAssertEqual(m.currentIndex, 1)
        XCTAssertEqual(m.current?.lastPathComponent, "b.jpg")
    }

    func testLoadWithoutCurrentStartsAtFirst() throws {
        XCTAssertEqual(try model(["a.jpg", "b.jpg"], current: nil).currentIndex, 0)
    }

    func testLoadOfEmptyFolderHasNoCurrent() throws {
        let m = try model([], current: nil)
        XCTAssertNil(m.currentIndex)
        XCTAssertNil(m.current)
    }

    func testLoadIncludesExplicitlyOpenedNonImage() throws {
        let m = try model(["a.jpg", "notes.txt"], current: "notes.txt")
        XCTAssertEqual(names(m), ["a.jpg", "notes.txt"])
        XCTAssertEqual(m.current?.lastPathComponent, "notes.txt")
    }

    func testFixedScopeKeepsDuplicatesAndSelectsByIndex() {
        let dir = Fixtures.tempDir()
        let a = dir.appendingPathComponent("a.jpg"), b = dir.appendingPathComponent("b.jpg")
        let m = FolderModel(folder: dir, files: [a, b, a], current: nil, scope: .fixed)
        XCTAssertEqual(m.currentIndex, 0)
        m.move(by: 2); XCTAssertEqual(m.currentIndex, 2)
        m.move(by: 1); XCTAssertEqual(m.currentIndex, 0)
    }

    func testMoveWrapsBothWays() throws {
        let m = try model(["a.jpg", "b.jpg", "c.jpg"], current: "c.jpg")
        m.move(by: 1); XCTAssertEqual(m.currentIndex, 0)
        m.move(by: -1); XCTAssertEqual(m.currentIndex, 2)
    }

    func testFirstAndLast() throws {
        let m = try model(["a.jpg", "b.jpg", "c.jpg"], current: "b.jpg")
        m.moveToLast(); XCTAssertEqual(m.currentIndex, 2)
        m.moveToFirst(); XCTAssertEqual(m.currentIndex, 0)
    }

    func testSelectURLAndOnChange() throws {
        let m = try model(["a.jpg", "b.jpg"], current: "a.jpg")
        var changes: [FolderModel.Change] = []
        m.onChange = { changes.append($0) }
        m.select(m.files[1])
        m.select(1) // no-op: already current
        XCTAssertEqual(changes, [.current])
    }

    func testReplaceKeepsCurrentFile() throws {
        let m = try model(["b.jpg", "c.jpg"], current: "c.jpg")
        m.replaceFiles([m.folder.appendingPathComponent("a.jpg")] + m.files)
        XCTAssertEqual(m.current?.lastPathComponent, "c.jpg")
        XCTAssertEqual(m.currentIndex, 2)
    }

    func testReplaceWhenCurrentDeletedMovesToNeighbour() throws {
        let m = try model(["a.jpg", "b.jpg", "c.jpg"], current: "b.jpg")
        var changes: [FolderModel.Change] = []
        m.onChange = { changes.append($0) }
        m.replaceFiles([m.files[0], m.files[2]])
        XCTAssertEqual(m.current?.lastPathComponent, "c.jpg")
        XCTAssertEqual(changes, [.files])

        m.replaceFiles([m.files[0]]) // current (last) deleted → clamps to new last
        XCTAssertEqual(m.current?.lastPathComponent, "a.jpg")
    }

    func testReplaceToEmptyClearsCurrent() throws {
        let m = try model(["a.jpg"], current: "a.jpg")
        m.replaceFiles([])
        XCTAssertNil(m.currentIndex)
        m.move(by: 1) // must not crash
        XCTAssertNil(m.current)
    }

    func testSelectingAFileAddedSinceTheLastScanSelectsIt() throws {
        let m = try model(["a.jpg"], current: "a.jpg")
        Fixtures.touch(["b.jpg"], in: m.folder)
        m.select(m.folder.appendingPathComponent("b.jpg"))
        XCTAssertEqual(m.current?.lastPathComponent, "b.jpg")
    }

    func testSymlinkedImageListsUnderItsOwnNameInTheFolder() throws {
        let dir = Fixtures.tempDir()
        let elsewhere = Fixtures.tempDir()
        Fixtures.touch(["real.jpg"], in: elsewhere)
        Fixtures.touch(["a.jpg"], in: dir)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link.jpg"),
                                                   withDestinationURL: elsewhere.appendingPathComponent("real.jpg"))
        XCTAssertEqual(names(try FolderModel.load(folder: dir)), ["a.jpg", "link.jpg"])
        let opened = try FolderModel.load(folder: dir, current: dir.appendingPathComponent("link.jpg"))
        XCTAssertEqual(opened.current?.lastPathComponent, "link.jpg")
        XCTAssertEqual(names(opened), ["a.jpg", "link.jpg"])
    }

    func testRescanPicksUpNewFiles() throws {
        let m = try model(["a.jpg"], current: "a.jpg")
        Fixtures.touch(["b.jpg"], in: m.folder)
        m.replaceFiles(try FolderModel.scan(m.folder))
        XCTAssertEqual(names(m), ["a.jpg", "b.jpg"])
    }
}
