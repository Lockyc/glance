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

    public init(folder: URL, files: [URL], current: URL?) {
        let normalised = files.map { $0.resolvingSymlinksInPath() }
        let wanted = current?.resolvingSymlinksInPath()
        self.folder = folder.resolvingSymlinksInPath()
        self.files = normalised
        self.currentIndex = wanted.flatMap { normalised.firstIndex(of: $0) } ?? (normalised.isEmpty ? nil : 0)
    }

    /// Viewable, non-hidden, non-directory entries in Finder's natural order (`img2` before `img10`).
    /// Skipping hidden files also drops AppleDouble `._*` companions on NAS/exFAT volumes.
    public static func scan(_ folder: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .contentTypeKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true && ImageTypes.isViewable($0) }
            .sorted(by: naturalOrder)
    }

    /// An explicitly opened file is always included, even if `scan` would filter it out —
    /// it then renders as "Can't open" instead of the app opening something else.
    public static func load(folder: URL, current: URL? = nil) throws -> FolderModel {
        var files = try scan(folder).map { $0.resolvingSymlinksInPath() }
        if let wanted = current?.resolvingSymlinksInPath(), !files.contains(wanted) {
            files.append(wanted)
            files.sort(by: naturalOrder)
        }
        return FolderModel(folder: folder, files: files, current: current)
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

    public func select(_ url: URL) {
        if let index = files.firstIndex(of: url.resolvingSymlinksInPath()) { select(index) }
    }

    /// Keeps the current file if it survived; otherwise the file that took its place, or the new last.
    public func replaceFiles(_ newFiles: [URL]) {
        let newFiles = newFiles.map { $0.resolvingSymlinksInPath() }
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
