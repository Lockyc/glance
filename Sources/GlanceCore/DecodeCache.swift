import Foundation

/// Keeps the current image and its neighbours (±radius, wrapping like navigation) decoded at
/// screen size, so ←/→ usually display a ready image. Work for files that leave the window is
/// cancelled, and any result that finishes anyway is dropped. Main-thread API.
public final class DecodeCache {
    public var onDecoded: ((URL, Result<DecodedImage, DecodeError>) -> Void)?

    /// What a decode was made from; a changed stamp means the file was re-saved or finished copying.
    struct Stamp: Equatable {
        let modified: Date?
        let size: Int?

        static func of(_ url: URL) -> Stamp? {
            var url = url
            url.removeAllCachedResourceValues()
            return (try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]))
                .map { Stamp(modified: $0.contentModificationDate, size: $0.fileSize) }
        }
    }

    private struct Entry {
        let stamp: Stamp?
        let result: Result<DecodedImage, DecodeError>
    }

    private let decoder: any ImageDecoding
    private let maxPixelSize: Int
    private let radius: Int
    private let queue = OperationQueue()
    private var window: Set<URL> = []
    private var focused: (index: Int, files: [URL]) = (0, [])
    private var entries: [URL: Entry] = [:]
    private var inFlight: [URL: Operation] = [:]

    public init(decoder: any ImageDecoding, maxPixelSize: Int, radius: Int = 2) {
        self.decoder = decoder
        self.maxPixelSize = maxPixelSize
        self.radius = radius
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .userInitiated
    }

    public func result(for url: URL) -> Result<DecodedImage, DecodeError>? { entries[url]?.result }

    public func clear() { focus(on: 0, in: []) }

    /// Re-decodes any held image whose file changed since it was decoded. The stat pass runs off
    /// the main thread (a NAS round trip per file); `onDecoded` reports each fresh result.
    public func revalidate() {
        let held = entries.mapValues(\.stamp)
        queue.addOperation { [weak self] in
            let changed = held.filter { Stamp.of($0.key) != $0.value }.map(\.key)
            guard !changed.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                changed.forEach { self.entries[$0] = nil }
                self.focus(on: self.focused.index, in: self.focused.files)
            }
        }
    }

    public func focus(on index: Int, in files: [URL]) {
        dispatchPrecondition(condition: .onQueue(.main))
        focused = (index, files)
        let ordered = files.isEmpty ? [] : Self.windowOrder(index: index, count: files.count, radius: radius).map { files[$0] }
        window = Set(ordered)
        entries = entries.filter { window.contains($0.key) }
        for (url, op) in inFlight where !window.contains(url) {
            op.cancel()
            inFlight[url] = nil
        }
        // Neighbours wait for the current image's decode, so it never shares the CPU with them.
        // A neighbour promoted to current sheds its wait on the old current and jumps the queue.
        var current = ordered.first.flatMap { inFlight[$0] }
        if let current, !current.isExecuting {
            current.dependencies.forEach(current.removeDependency)
            current.queuePriority = .veryHigh
        }
        for (rank, url) in ordered.enumerated() where entries[url] == nil && inFlight[url] == nil {
            let op = BlockOperation()
            op.queuePriority = rank == 0 ? .veryHigh : .normal
            if rank == 0 { current = op } else if let current { op.addDependency(current) }
            op.addExecutionBlock { [weak self, weak op, decoder, maxPixelSize] in
                guard let op, !op.isCancelled else { return }
                let stamp = Stamp.of(url)
                let result = decoder.decode(url, maxPixelSize: maxPixelSize)
                DispatchQueue.main.async { self?.finish(url, op, Entry(stamp: stamp, result: result)) }
            }
            inFlight[url] = op
            queue.addOperation(op)
        }
    }

    private func finish(_ url: URL, _ op: Operation, _ entry: Entry) {
        guard inFlight[url] === op else { return }
        inFlight[url] = nil
        guard window.contains(url) else { return }
        entries[url] = entry
        onDecoded?(url, entry.result)
    }

    /// `[index, index+1, index-1, index+2, index-2, …]`, wrapped and de-duplicated.
    static func windowOrder(index: Int, count: Int, radius: Int) -> [Int] {
        var order: [Int] = []
        for offset in [0] + (1...max(1, radius)).flatMap({ [$0, -$0] }) {
            let i = ((index + offset) % count + count) % count
            if !order.contains(i) { order.append(i) }
        }
        return order
    }
}
