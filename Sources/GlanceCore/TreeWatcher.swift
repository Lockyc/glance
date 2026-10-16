import CoreServices
import Foundation

/// Watches a folder — and, when `recursive`, everything under it — through FSEvents. A burst of
/// events produces one callback after `debounce` seconds of quiet, carrying the folders whose
/// entries changed, or `.everything` when FSEvents dropped events or the folder itself moved.
public final class TreeWatcher {
    public enum Change: Equatable {
        case directories(Set<URL>)
        case everything

        public func merged(with other: Change) -> Change {
            if case .directories(let a) = self, case .directories(let b) = other { return .directories(a.union(b)) }
            return .everything
        }
    }

    private let root: URL
    private let recursive: Bool
    private let debounce: TimeInterval
    private let onChange: (Change) -> Void
    private var stream: FSEventStreamRef?
    private var pending: Change?
    private var flush: DispatchWorkItem?

    public init?(folder: URL, recursive: Bool, debounce: TimeInterval = 0.1, onChange: @escaping (Change) -> Void) {
        // FSEvents needs the real path (/private/var, not /var) to match events.
        guard let real = realpath(folder.path, nil) else { return nil }
        let realPath = String(cString: real)
        free(real)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: realPath, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        root = folder.resolvingSymlinksInPath()
        self.recursive = recursive
        self.debounce = debounce
        self.onChange = onChange

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<TreeWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            watcher.received(list, Array(UnsafeBufferPointer(start: flags, count: count)))
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [realPath] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    deinit {
        flush?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func received(_ paths: [String], _ flags: [FSEventStreamEventFlags]) {
        let rescan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                                             | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)
        var change = Change.directories([])
        for (path, flag) in zip(paths, flags) {
            if flag & rescan != 0 { change = .everything; continue }
            let dir = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
            guard recursive || dir.path == root.path else { continue }
            change = change.merged(with: .directories([URL(fileURLWithPath: dir.path, isDirectory: true)]))
        }
        if change == .directories([]) { return }
        pending = pending.map { $0.merged(with: change) } ?? change
        flush?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let pending = self.pending else { return }
            self.pending = nil
            self.onChange(pending)
        }
        flush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
