import Foundation

/// Folders browsed together with everything under them ("roots"), each with the subfolders it
/// leaves out. Stored in user defaults; posts `didChange` after every change.
public final class SubfolderRoots {
    public struct Root: Codable, Equatable {
        /// Canonical (`resolvingSymlinksInPath`), the same form as `FolderModel.folder`.
        public let path: String
        /// Folder paths relative to `path`, at any depth, sorted.
        public var excluded: [String]
        public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    }

    public static let didChange = Notification.Name("SubfolderRootsDidChange")
    public static let shared = SubfolderRoots(defaults: .standard)

    private let defaults: UserDefaults
    private let key: String
    public private(set) var roots: [Root]

    public init(defaults: UserDefaults, key: String = "subfolderRoots") {
        self.defaults = defaults
        self.key = key
        roots = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Root].self, from: $0) } ?? []
    }

    private static func canonicalPath(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

    public func root(at folder: URL) -> Root? {
        let path = Self.canonicalPath(folder)
        return roots.first { $0.path == path }
    }

    /// The deepest root whose tree holds `url` without passing through one of its excluded
    /// folders. `url` must already be canonical (`FolderModel.canonical` for a file).
    public func root(covering url: URL) -> Root? {
        roots.filter { root in
            guard let relative = Self.relativePath(of: url, in: root.url) else { return false }
            return !Self.isExcluded(relative, by: root.excluded)
        }.max { $0.path.count < $1.path.count }
    }

    /// Whether the folder or file at `relative` is one of `excluded` or inside one.
    public static func isExcluded(_ relative: String, by excluded: some Sequence<String>) -> Bool {
        excluded.contains { relative == $0 || relative.hasPrefix($0 + "/") }
    }

    /// `url`'s path below `folder` ("" for the folder itself), or nil when it is not inside it.
    public static func relativePath(of url: URL, in folder: URL) -> String? {
        let path = url.path, base = folder.path
        if path == base { return "" }
        return path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : nil
    }

    public func enable(_ folder: URL) {
        guard root(at: folder) == nil else { return }
        roots.append(Root(path: Self.canonicalPath(folder), excluded: []))
        save()
    }

    public func disable(_ folder: URL) {
        let path = Self.canonicalPath(folder)
        roots.removeAll { $0.path == path }
        save()
    }

    /// `relative` is a folder path under the root, as `relativePath` returns it.
    public func setExcluded(_ relative: String, _ excluded: Bool, in folder: URL) {
        let path = Self.canonicalPath(folder)
        guard !relative.isEmpty, let index = roots.firstIndex(where: { $0.path == path }) else { return }
        var set = Set(roots[index].excluded)
        if excluded { set.insert(relative) } else { set.remove(relative) }
        roots[index].excluded = set.sorted()
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(roots), forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
