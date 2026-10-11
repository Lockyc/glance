import Foundation

/// The viewable images of one folder in Finder order, and which one is current.
/// Viewer and grid share one instance so they never disagree about position.
public final class FolderModel {
    public enum Change: Equatable { case files, current }

    public let folder: URL
    public private(set) var files: [URL]
    /// `nil` exactly when `files` is empty.
    public private(set) var currentIndex: Int?
    public var onChange: ((Change) -> Void)?

    public var current: URL? { currentIndex.map { files[$0] } }

    /// `files` must already be canonical (as `scan` returns them); `current` is canonicalised here.
    public init(folder: URL, files: [URL], current: URL?) {
        let wanted = current.map(Self.canonical)
        self.folder = folder.resolvingSymlinksInPath()
        self.files = files
        self.currentIndex = wanted.flatMap { files.firstIndex(of: $0) } ?? (files.isEmpty ? nil : 0)
    }

    /// The folder resolved once, the file name kept: one realpath per URL instead of one per
    /// listed file (each a round trip on a network volume), and a symlinked image keeps its own name.
    public static func canonical(_ url: URL) -> URL {
        url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent)
    }

    /// Viewable, non-hidden, non-directory entries in Finder's natural order (`img2` before `img10`).
    /// Skipping hidden files also drops AppleDouble `._*` companions on NAS/exFAT volumes.
    /// Entries are rebuilt on the same base as `canonical`: the directory listing reports the
    /// realpath (`/private/var/…`) while `resolvingSymlinksInPath` strips `/private`.
    public static func scan(_ folder: URL) throws -> [URL] {
        let base = folder.resolvingSymlinksInPath()
        return try FileManager.default
            .contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey, .contentTypeKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true && ImageTypes.isViewable($0) }
            .map { base.appendingPathComponent($0.lastPathComponent) }
            .sorted(by: naturalOrder)
    }

    /// An explicitly opened file is always included, even if `scan` would filter it out —
    /// it then renders as "Can't open" instead of the app opening something else.
    public static func load(folder: URL, current: URL? = nil) throws -> FolderModel {
        FolderModel(folder: folder, files: try listing(folder, including: current), current: current)
    }

    /// `scan` plus the explicitly opened file. Blocking I/O: call off the main thread.
    public static func listing(_ folder: URL, including current: URL?) throws -> [URL] {
        inserting(current.map(canonical), into: try scan(folder))
    }

    private static func inserting(_ url: URL?, into files: [URL]) -> [URL] {
        guard let url, !files.contains(url) else { return files }
        return (files + [url]).sorted(by: naturalOrder)
    }

    static func naturalOrder(_ a: URL, _ b: URL) -> Bool {
        a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
    }

    public func move(by delta: Int) {
        guard let index = currentIndex else { return }
        let count = files.count
        select(((index + delta) % count + count) % count)
    }

    public func moveToFirst() { select(0) }
    public func moveToLast() { select(files.count - 1) }

    public func select(_ index: Int) {
        guard files.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        onChange?(.current)
    }

    /// A file that arrived since the last scan (opened before the watcher.s debounce fires) is
    /// inserted rather than ignored; the next scan reconciles the list.
    public func select(_ url: URL) {
        let url = Self.canonical(url)
        if !files.contains(url) { replaceFiles(Self.inserting(url, into: files)) }
        if let index = files.firstIndex(of: url) { select(index) }
    }

    /// Keeps the current file if it survived; otherwise the file that took its place, or the new last.
    public func replaceFiles(_ newFiles: [URL]) {
        guard newFiles != files else { return }
        let previous = current
        let previousIndex = currentIndex ?? 0
        files = newFiles
        if let previous, let index = files.firstIndex(of: previous) {
            currentIndex = index
        } else {
            currentIndex = files.isEmpty ? nil : min(previousIndex, files.count - 1)
        }
        onChange?(.files)
    }

    public func rescan() throws {
        replaceFiles(try Self.scan(folder))
    }
}
