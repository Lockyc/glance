@testable import GlanceCore
import XCTest

final class FolderTreeTests: XCTestCase {
    private func names(_ listing: FolderModel.Listing) -> [String] { listing.files.map(\.lastPathComponent) }

    func testTreeListsEveryDepthOldestFirst() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("2025/03/b.png", in: root, created: Fixtures.day(2))
        Fixtures.file("2025/04/c.png", in: root, created: Fixtures.day(30))
        Fixtures.file("a.png", in: root, created: Fixtures.day(0))
        Fixtures.file("loose.png", in: root, created: Fixtures.day(60))
        let listing = try FolderModel.scanTree(root, excluded: [])
        XCTAssertEqual(names(listing), ["a.png", "b.png", "c.png", "loose.png"])
        XCTAssertEqual(listing.dates, [0, 2, 30, 60].map(Fixtures.day))
    }

    func testTreeSkipsExcludedHiddenNonImagesAndPDF() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("keep/a.png", in: root, created: Fixtures.day(0))
        Fixtures.file("timeline/2026-07-07/t.png", in: root, created: Fixtures.day(1))
        Fixtures.file("deep/skip/s.png", in: root, created: Fixtures.day(2))
        Fixtures.file(".hidden/h.png", in: root, created: Fixtures.day(3))
        Fixtures.file("keep/._a.png", in: root, created: Fixtures.day(4))
        Fixtures.file("keep/notes.txt", in: root, created: Fixtures.day(5))
        Fixtures.file("keep/doc.pdf", in: root, created: Fixtures.day(6))
        let listing = try FolderModel.scanTree(root, excluded: ["timeline", "deep/skip"])
        XCTAssertEqual(names(listing), ["a.png"])
    }

    func testTreeDoesNotFollowSymlinkedFolders() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("a.png", in: root, created: Fixtures.day(0))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        XCTAssertEqual(names(try FolderModel.scanTree(root, excluded: [])), ["a.png"])
    }

    func testSameDateOrdersByNaturalName() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("x/img10.png", in: root, created: Fixtures.day(0))
        Fixtures.file("y/img2.png", in: root, created: Fixtures.day(0))
        XCTAssertEqual(names(try FolderModel.scanTree(root, excluded: [])), ["img2.png", "img10.png"])
    }

    func testTreeFilesAreCanonicalLikeFlatScan() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("sub/a.png", in: root, created: Fixtures.day(0))
        let file = try XCTUnwrap(try FolderModel.scanTree(root, excluded: []).files.first)
        XCTAssertEqual(file, FolderModel.canonical(root.appendingPathComponent("sub/a.png")))
    }

    func testListingIncludesExplicitlyOpenedNonImageInDateOrder() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("a.png", in: root, created: Fixtures.day(0))
        Fixtures.file("sub/notes.txt", in: root, created: Fixtures.day(1))
        Fixtures.file("c.png", in: root, created: Fixtures.day(2))
        let listing = try FolderModel.listing(root, scope: .tree(excluded: []), including: root.appendingPathComponent("sub/notes.txt"))
        XCTAssertEqual(names(listing), ["a.png", "notes.txt", "c.png"])
        XCTAssertEqual(listing.dates.count, 3)
    }

    func testFlatListingIsUnchangedAndHasNoDates() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("b.png", in: root, created: Fixtures.day(0))
        Fixtures.file("a.png", in: root, created: Fixtures.day(1))
        Fixtures.file("sub/c.png", in: root, created: Fixtures.day(2))
        let listing = try FolderModel.listing(root, including: nil)
        XCTAssertEqual(names(listing), ["a.png", "b.png"])
        XCTAssertEqual(listing.dates, [])
    }

    func testSelectingAnUnlistedFileInATreeInsertsItByDate() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("a.png", in: root, created: Fixtures.day(0))
        Fixtures.file("c.png", in: root, created: Fixtures.day(2))
        let model = try FolderModel.load(folder: root, scope: .tree(excluded: []))
        Fixtures.file("sub/b.png", in: root, created: Fixtures.day(1))
        model.select(root.appendingPathComponent("sub/b.png"))
        XCTAssertEqual(model.files.map(\.lastPathComponent), ["a.png", "b.png", "c.png"])
        XCTAssertEqual(model.dates.count, 3)
        XCTAssertEqual(model.currentIndex, 1)
    }
}
