import Foundation

/// The viewable images of one folder — or, for a tree, everything under it — and which one is current.
/// Viewer and grid share one instance so they never disagree about position.
public final class FolderModel {
    public enum Change: Equatable { case files, current }

    public enum Scope: Equatable {
        /// The folder's own images in Finder's natural order.
        case flat
        /// Every image under the folder, oldest first; `excluded` are folder paths relative to it.
        case tree(excluded: Set<String>)
    }

    public struct Listing: Equatable {
        public var files: [URL]
        /// Creation dates parallel to `files` for a tree; empty for a flat folder.
        public var dates: [Date]
        public init(files: [URL], dates: [Date] = []) {
            self.files = files
            self.dates = dates
        }
    }

    struct Entry: Equatable {
        let url: URL
        let date: Date
        /// `url.path`, computed once: `relist` tests every entry's path against each changed folder.
        let path: String

        init(url: URL, date: Date) {
            self.url = url
            self.date = date
            path = url.path
        }
    }

    public let folder: URL
    public private(set) var files: [URL]
    public private(set) var scope: Scope
    public private(set) var dates: [Date]
    /// `nil` exactly when `files` is empty.
    public private(set) var currentIndex: Int?
    public var onChange: ((Change) -> Void)?

    public var current: URL? { currentIndex.map { files[$0] } }
    public var listing: Listing { Listing(files: files, dates: dates) }

    /// `files` must already be canonical (as `scan` returns them); `current` is canonicalised here.
    public init(folder: URL, files: [URL], current: URL?, scope: Scope = .flat, dates: [Date] = []) {
        let wanted = current.map(Self.canonical)
        self.folder = folder.resolvingSymlinksInPath()
        self.files = files
        self.scope = scope
        self.dates = dates
        self.currentIndex = wanted.flatMap { files.firstIndex(of: $0) } ?? (files.isEmpty ? nil : 0)
    }

    /// The caller rescans; the list keeps its old contents until then.
    public func setScope(_ scope: Scope) { self.scope = scope }

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

    /// Every viewable image under `root`, oldest first (creation date, else modification date;
    /// ties by natural name, then path). Hidden entries, excluded folders and symlinked folders
    /// are skipped. Only an unreadable `root` throws; an unreadable subfolder is left out.
    public static func scanTree(_ root: URL, excluded: Set<String>) throws -> Listing {
        var entries: [Entry] = []
        try walk(root.resolvingSymlinksInPath(), relative: "", excluded: excluded, into: &entries)
        return sorted(entries)
    }

    /// `listing` with the folders in `changed` re-read: each one's own images replaced, a subfolder
    /// that appeared walked whole, one that vanished dropped with everything under it. Folders
    /// outside `root`, inside an excluded folder, or inside a hidden one (which `walk` never
    /// enters) are ignored. Parents are handled before their
    /// children, so a new folder reported on both levels is not listed twice.
    public static func relist(_ listing: Listing, root: URL, excluded: Set<String>, changed: Set<URL>) -> Listing {
        var entries = zip(listing.files, listing.dates).map(Entry.init)
        for dir in changed.map({ URL(fileURLWithPath: $0.path, isDirectory: true) }).sorted(by: { $0.path.count < $1.path.count }) {
            guard let relative = SubfolderRoots.relativePath(of: dir, in: root),
                  !SubfolderRoots.isExcluded(relative, by: excluded),
                  !relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { continue }
            let prefix = dir.path + "/"
            let isUnder = { (entry: Entry) in entry.path.hasPrefix(prefix) }
            guard let (images, folders) = try? read(dir) else {
                entries.removeAll(where: isUnder)
                continue
            }
            let present = Set(folders.filter { !excluded.contains(child(of: relative, $0)) })
            var held = Set<String>()
            // Own images go (re-added below); images in folders that vanished go; the rest stay.
            entries.removeAll { entry in
                guard isUnder(entry) else { return false }
                guard let top = topFolder(of: entry.path, under: prefix) else { return true }
                held.insert(top)
                return !present.contains(top)
            }
            entries += images
            for name in present.subtracting(held) {
                try? walk(dir.appendingPathComponent(name), relative: child(of: relative, name), excluded: excluded, into: &entries)
            }
        }
        return sorted(entries)
    }

    /// The first folder name below `prefix` in `url`'s path; nil for a file directly in it.
    private static func topFolder(of path: String, under prefix: String) -> String? {
        let rest = path.dropFirst(prefix.count)
        return rest.firstIndex(of: "/").map { String(rest[..<$0]) }
    }

    /// A subfolder's path relative to the root, in the form `excluded` holds.
    private static func child(of relative: String, _ name: String) -> String {
        relative.isEmpty ? name : relative + "/" + name
    }

    static func walk(_ dir: URL, relative: String, excluded: Set<String>, into entries: inout [Entry]) throws {
        let (images, folders) = try read(dir)
        entries += images
        for name in folders {
            let path = child(of: relative, name)
            guard !excluded.contains(path) else { continue }
            try? walk(dir.appendingPathComponent(name), relative: path, excluded: excluded, into: &entries)
        }
    }

    /// One directory: its images (dated) and the names of its subfolders. Entries are rebuilt on
    /// `dir`, as in `scan`, so they match `canonical`. A symlink reports `isDirectory == false`,
    /// so symlinked folders are never descended.
    static func read(_ dir: URL) throws -> (images: [Entry], folders: [String]) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentTypeKey, .creationDateKey, .contentModificationDateKey]
        var images: [Entry] = []
        var folders: [String] = []
        for child in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            let values = try? child.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                folders.append(child.lastPathComponent)
            } else if ImageTypes.isViewable(child) {
                images.append(Entry(url: dir.appendingPathComponent(child.lastPathComponent), date: date(values)))
            }
        }
        return (images, folders)
    }

    private static func date(_ values: URLResourceValues?) -> Date {
        values?.creationDate ?? values?.contentModificationDate ?? .distantPast
    }

    private static func entry(_ url: URL) -> Entry {
        Entry(url: url, date: date(try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])))
    }

    static func sorted(_ entries: [Entry]) -> Listing {
        let ordered = entries.sorted(by: chronological)
        return Listing(files: ordered.map(\.url), dates: ordered.map(\.date))
    }

    static func chronological(_ a: Entry, _ b: Entry) -> Bool {
        if a.date != b.date { return a.date < b.date }
        let byName = a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent)
        return byName != .orderedSame ? byName == .orderedAscending : a.path < b.path
    }

    /// An explicitly opened file is always included, even if a scan would filter it out —
    /// it then renders as "Can't open" instead of the app opening something else.
    public static func load(folder: URL, current: URL? = nil, scope: Scope = .flat) throws -> FolderModel {
        let listing = try listing(folder, scope: scope, including: current)
        return FolderModel(folder: folder, files: listing.files, current: current, scope: scope, dates: listing.dates)
    }

    /// The scan for `scope` plus the explicitly opened file. Blocking I/O: call off the main thread.
    public static func listing(_ folder: URL, scope: Scope = .flat, including current: URL?) throws -> Listing {
        switch scope {
        case .flat: return inserting(current.map(canonical), into: Listing(files: try scan(folder)), tree: false)
        case .tree(let excluded): return inserting(current.map(canonical), into: try scanTree(folder, excluded: excluded), tree: true)
        }
    }

    /// A flat listing keeps natural order; a tree places the file by its creation date. The
    /// caller says which, because an empty tree has no dates to tell them apart.
    private static func inserting(_ url: URL?, into listing: Listing, tree: Bool) -> Listing {
        guard let url, !listing.files.contains(url) else { return listing }
        guard tree else { return Listing(files: (listing.files + [url]).sorted(by: naturalOrder)) }
        return sorted(zip(listing.files, listing.dates).map(Entry.init) + [entry(url)])
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

    /// A file that arrived since the last scan (opened before the watcher's debounce fires) is
    /// inserted rather than ignored; the next scan reconciles the list.
    public func select(_ url: URL) {
        let url = Self.canonical(url)
        if !files.contains(url) {
            let updated = Self.inserting(url, into: listing, tree: scope != .flat)
            replaceFiles(updated.files, dates: updated.dates)
        }
        if let index = files.firstIndex(of: url) { select(index) }
    }

    /// Keeps the current file if it survived; otherwise the file that took its place, or the new last.
    public func replaceFiles(_ newFiles: [URL], dates newDates: [Date] = []) {
        guard newFiles != files || newDates != dates else { return }
        let previous = current
        let previousIndex = currentIndex ?? 0
        files = newFiles
        dates = newDates
        if let previous, let index = files.firstIndex(of: previous) {
            currentIndex = index
        } else {
            currentIndex = files.isEmpty ? nil : min(previousIndex, files.count - 1)
        }
        onChange?(.files)
    }
}
