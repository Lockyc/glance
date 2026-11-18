import Exhaust
@testable import GlanceCore
import XCTest

/// `FolderModel.relist` against the full walk it shortcuts: after any sequence of tree edits, re-reading
/// only the folders whose entries changed must give exactly what `scanTree` gives from scratch.
final class RelistModelTests: XCTestCase {
    func testRelistEqualsAFreshScanAfterAnyEdits() async {
        await #execute(RelistSpec.self, mode: .sequential, .commandLimit(15))
    }

    /// An image written under a hidden folder (`.h/x.png`), then a relist: the walk never enters it.
    func testRelistReplaysTheHiddenFolderCase() async {
        await #execute(RelistSpec.self, mode: .sequential, .commandLimit(15), .replay("A8ATY6NSM46XW-26"))
    }
}

@StateMachine
final class RelistSpec {
    /// Folder names: plain, hidden, excluded at the root (`timeline`), excluded below it (`a/b`).
    static let folders = ["a", "b", "timeline", ".h", "c"]
    static let images = ["x.png", "y.png", ".z.png"]
    static let excluded: Set<String> = ["timeline", "a/b"]

    let root: URL
    /// Folders whose entries changed since the last relist, relative to `root`: what FSEvents reports.
    var changed: Set<String> = []
    @SystemUnderTest var listing = FolderModel.Listing(files: [])

    init() {
        root = Fixtures.tempDir().resolvingSymlinksInPath()
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    private func path(_ components: [Int]) -> String {
        components.map { Self.folders[$0 % Self.folders.count] }.joined(separator: "/")
    }

    private func url(_ relative: String) -> URL {
        relative.isEmpty ? root : root.appendingPathComponent(relative, isDirectory: true)
    }

    private func exists(_ relative: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url(relative).path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func parent(_ relative: String) -> String {
        relative.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// `relative` and every ancestor that did not exist yet: each new folder changes its parent's entries.
    private func makeFolders(_ relative: String) {
        var current = relative
        while !current.isEmpty, !exists(current) {
            changed.insert(parent(current))
            current = parent(current)
        }
        try? FileManager.default.createDirectory(at: url(relative), withIntermediateDirectories: true)
    }

    /// Every folder at or under `relative`, which all lose their entries when it goes.
    private func folders(under relative: String) -> [String] {
        let base = url(relative)
        let found = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey])?
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { SubfolderRoots.relativePath(of: $0.resolvingSymlinksInPath(), in: root) } ?? []
        return [relative] + found
    }

    @Command(weight: 4, .int(in: 0...4).array(length: 0...3), .int(in: 0...2), .int(in: 0...3))
    func addImage(folder: [Int], name: Int, day: Int) throws {
        let dir = path(folder)
        makeFolders(dir)
        let file = (dir.isEmpty ? "" : dir + "/") + Self.images[name]
        Fixtures.file(file, in: root, created: Fixtures.day(day))
        changed.insert(dir)
    }

    @Command(weight: 2, .int(in: 0...4).array(length: 0...3), .int(in: 0...2))
    func deleteImage(folder: [Int], name: Int) throws {
        let dir = path(folder)
        let file = url(dir).appendingPathComponent(Self.images[name])
        guard FileManager.default.fileExists(atPath: file.path) else { throw skip() }
        try FileManager.default.removeItem(at: file)
        changed.insert(dir)
    }

    @Command(weight: 1, .int(in: 0...4).array(length: 1...3))
    func makeFolder(folder: [Int]) throws {
        let dir = path(folder)
        guard !exists(dir) else { throw skip() }
        makeFolders(dir)
    }

    @Command(weight: 2, .int(in: 0...4).array(length: 1...3))
    func removeFolder(folder: [Int]) throws {
        let dir = path(folder)
        guard exists(dir) else { throw skip() }
        changed.formUnion(folders(under: dir))
        changed.insert(parent(dir))
        try FileManager.default.removeItem(at: url(dir))
    }

    @Command(weight: 2, .int(in: 0...4).array(length: 1...3), .int(in: 0...4))
    func renameFolder(folder: [Int], to name: Int) throws {
        let dir = path(folder)
        let parentDir = parent(dir)
        let target = (parentDir.isEmpty ? "" : parentDir + "/") + Self.folders[name]
        guard exists(dir), !FileManager.default.fileExists(atPath: url(target).path) else { throw skip() }
        try FileManager.default.moveItem(at: url(dir), to: url(target))
        changed.insert(parentDir)
    }

    /// FSEvents may also report folders that did not change, or that no longer exist.
    @Command(weight: 3, .int(in: 0...4).array(length: 0...3).array(length: 0...2))
    func relist(extra: [[Int]]) throws {
        let dirs = changed.union(extra.map(path))
        listing = FolderModel.relist(listing, root: root, excluded: Self.excluded, changed: Set(dirs.map(url)))
        changed = []
        let scanned = try FolderModel.scanTree(root, excluded: Self.excluded)
        try check(listing == scanned, "relist must equal a fresh scanTree")
    }

    func failureDescription() -> String? {
        let scanned = try? FolderModel.scanTree(root, excluded: Self.excluded)
        func show(_ files: [URL]?) -> String {
            (files ?? []).compactMap { SubfolderRoots.relativePath(of: $0, in: root) }.joined(separator: ", ")
        }
        return "relisted: [\(show(listing.files))]\nscanned:  [\(show(scanned?.files))]\npending: \(changed.sorted())"
    }
}
