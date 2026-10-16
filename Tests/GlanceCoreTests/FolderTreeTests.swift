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

    private func relist(_ root: URL, _ listing: FolderModel.Listing, _ dirs: [String]) -> FolderModel.Listing {
        let base = root.resolvingSymlinksInPath()
        let changed = Set(dirs.map { $0.isEmpty ? base : base.appendingPathComponent($0, isDirectory: true) })
        return FolderModel.relist(listing, root: base, excluded: ["timeline"], changed: changed)
    }

    func testRelistMatchesAFullScanAfterAdditionsAndRemovals() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("2025/03/a.png", in: root, created: Fixtures.day(0))
        Fixtures.file("2025/03/b.png", in: root, created: Fixtures.day(1))
        Fixtures.file("loose.png", in: root, created: Fixtures.day(5))
        let before = try FolderModel.scanTree(root, excluded: ["timeline"])
        Fixtures.file("2025/03/c.png", in: root, created: Fixtures.day(2))
        try FileManager.default.removeItem(at: root.appendingPathComponent("2025/03/a.png"))
        let after = relist(root, before, ["2025/03"])
        XCTAssertEqual(after, try FolderModel.scanTree(root, excluded: ["timeline"]))
    }

    func testRelistWalksANewSubfolderReportedOnlyOnItsParent() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("a.png", in: root, created: Fixtures.day(0))
        let before = try FolderModel.scanTree(root, excluded: ["timeline"])
        Fixtures.file("2026/10/new.png", in: root, created: Fixtures.day(9))
        Fixtures.file("2026/10/deeper/x.png", in: root, created: Fixtures.day(10))
        XCTAssertEqual(relist(root, before, [""]).files.map(\.lastPathComponent), ["a.png", "new.png", "x.png"])
    }

    func testRelistOfParentAndNewChildTogetherHasNoDuplicates() throws {
        let root = Fixtures.tempDir()
        let before = try FolderModel.scanTree(root, excluded: ["timeline"])
        Fixtures.file("2026/n.png", in: root, created: Fixtures.day(0))
        XCTAssertEqual(relist(root, before, ["", "2026"]).files.map(\.lastPathComponent), ["n.png"])
    }

    func testRenamedSubfolderReplacesItsEntries() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("old/a.png", in: root, created: Fixtures.day(0))
        Fixtures.file("old/inner/b.png", in: root, created: Fixtures.day(1))
        let before = try FolderModel.scanTree(root, excluded: ["timeline"])
        try FileManager.default.moveItem(at: root.appendingPathComponent("old"), to: root.appendingPathComponent("new"))
        let after = relist(root, before, [""])
        XCTAssertEqual(after, try FolderModel.scanTree(root, excluded: ["timeline"]))
        XCTAssertTrue(after.files.allSatisfy { $0.path.contains("/new/") })
    }

    func testDeletedFolderDropsEverythingUnderIt() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("gone/a.png", in: root, created: Fixtures.day(0))
        Fixtures.file("gone/x/b.png", in: root, created: Fixtures.day(1))
        Fixtures.file("keep.png", in: root, created: Fixtures.day(2))
        let before = try FolderModel.scanTree(root, excluded: ["timeline"])
        try FileManager.default.removeItem(at: root.appendingPathComponent("gone"))
        XCTAssertEqual(relist(root, before, ["gone"]).files.map(\.lastPathComponent), ["keep.png"])
    }

    func testChangesInsideExcludedFoldersAreIgnored() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("a.png", in: root, created: Fixtures.day(0))
        let before = try FolderModel.scanTree(root, excluded: ["timeline"])
        Fixtures.file("timeline/d/t.png", in: root, created: Fixtures.day(1))
        XCTAssertEqual(relist(root, before, ["timeline/d", ""]), before)
    }

    /// CleanShot files a loose screenshot into its month folder: same file, new path, same date.
    func testFileMovedIntoASubfolderStaysCurrent() throws {
        let root = Fixtures.tempDir()
        Fixtures.file("2026/10/a.png", in: root, created: Fixtures.day(0))
        Fixtures.file("shot.png", in: root, created: Fixtures.day(1))
        Fixtures.file("z.png", in: root, created: Fixtures.day(2))
        let model = try FolderModel.load(folder: root, current: root.appendingPathComponent("shot.png"), scope: .tree(excluded: []))
        try FileManager.default.moveItem(at: root.appendingPathComponent("shot.png"), to: root.appendingPathComponent("2026/10/shot.png"))
        let after = relist(root, model.listing, ["", "2026/10"])
        model.replaceFiles(after.files, dates: after.dates)
        XCTAssertEqual(model.files.map(\.lastPathComponent), ["a.png", "shot.png", "z.png"])
        XCTAssertEqual(model.current?.path, FolderModel.canonical(root.appendingPathComponent("2026/10/shot.png")).path)
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
