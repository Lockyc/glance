import Foundation

/// Keeps the current image and its neighbours (±radius, wrapping like navigation) decoded at
/// screen size, so ←/→ usually display a ready image. Work for files that leave the window is
/// cancelled, and any result that finishes anyway is dropped. Main-thread API.
public final class DecodeCache {
    public var onDecoded: ((URL, Result<DecodedImage, DecodeError>) -> Void)?

    private let decoder: any ImageDecoding
    private let maxPixelSize: Int
    private let radius: Int
    private let queue = OperationQueue()
    private var window: Set<URL> = []
    private var entries: [URL: Result<DecodedImage, DecodeError>] = [:]
    private var inFlight: [URL: Operation] = [:]

    public init(decoder: any ImageDecoding, maxPixelSize: Int, radius: Int = 2) {
        self.decoder = decoder
        self.maxPixelSize = maxPixelSize
        self.radius = radius
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .userInitiated
    }

    public func result(for url: URL) -> Result<DecodedImage, DecodeError>? { entries[url] }

    public func clear() { focus(on: 0, in: []) }

    public func focus(on index: Int, in files: [URL]) {
        dispatchPrecondition(condition: .onQueue(.main))
        let ordered = files.isEmpty ? [] : Self.windowOrder(index: index, count: files.count, radius: radius).map { files[$0] }
        window = Set(ordered)
        entries = entries.filter { window.contains($0.key) }
        for (url, op) in inFlight where !window.contains(url) {
            op.cancel()
            inFlight[url] = nil
        }
        // Neighbours wait for the current image's decode, so it never shares the CPU with them.
        var current = ordered.first.flatMap { inFlight[$0] }
        for (rank, url) in ordered.enumerated() where entries[url] == nil && inFlight[url] == nil {
            let op = BlockOperation()
            op.queuePriority = rank == 0 ? .veryHigh : .normal
            if rank == 0 { current = op } else if let current { op.addDependency(current) }
            op.addExecutionBlock { [weak self, weak op, decoder, maxPixelSize] in
                guard let op, !op.isCancelled else { return }
                let result = decoder.decode(url, maxPixelSize: maxPixelSize)
                DispatchQueue.main.async { self?.finish(url, op, result) }
            }
            inFlight[url] = op
            queue.addOperation(op)
        }
    }

    private func finish(_ url: URL, _ op: Operation, _ result: Result<DecodedImage, DecodeError>) {
        guard inFlight[url] === op else { return }
        inFlight[url] = nil
        guard window.contains(url) else { return }
        entries[url] = result
        onDecoded?(url, result)
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
