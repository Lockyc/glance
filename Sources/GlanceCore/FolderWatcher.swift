import Foundation

/// Watches one directory for entries being added, removed or renamed. A burst of events
/// (a copy of 500 files) produces one callback after `debounce` seconds of quiet.
public final class FolderWatcher {
    private let source: DispatchSourceFileSystemObject
    private var pending: DispatchWorkItem?

    public init?(folder: URL, debounce: TimeInterval = 0.1, onChange: @escaping () -> Void) {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            self.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit {
        pending?.cancel()
        source.cancel()
    }
}
