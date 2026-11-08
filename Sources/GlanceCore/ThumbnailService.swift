import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Grid thumbnails and hover previews: memory cache (evicts under pressure), then a disk
/// cache keyed by path + mtime + size + pixel size, then — for a file iCloud has evicted — the
/// cloud's stored thumbnail, then a real decode. Failures are never
/// cached, so a file still being copied in gets a fresh attempt on the next request.
public final class ThumbnailService {
    public static let defaultCacheDirectory = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("glance/thumbnails", isDirectory: true)

    private let decoder: any ImageDecoding
    private let cloud: any CloudThumbnailing
    private let cacheDirectory: URL
    private let memory = NSCache<NSString, CGImage>()
    private let queue = OperationQueue()

    public init(decoder: any ImageDecoding = ImageDecoder(), cloud: any CloudThumbnailing = QuickLookCloudThumbnails(),
                cacheDirectory: URL = defaultCacheDirectory) {
        self.decoder = decoder
        self.cloud = cloud
        self.cacheDirectory = cacheDirectory
        memory.totalCostLimit = 256 << 20
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
        queue.qualityOfService = .userInitiated
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    @discardableResult
    public func request(_ url: URL, pixelSize: Int, completion: @escaping (Result<CGImage, DecodeError>) -> Void) -> ThumbnailRequest {
        let request = ThumbnailRequest()
        let deliver: (Result<CGImage, DecodeError>) -> Void = { result in
            DispatchQueue.main.async { if !request.isCancelled { completion(result) } }
        }
        let op = BlockOperation { [weak self] in
            guard let self, !request.isCancelled else { return }
            switch self.lookup(url, pixelSize: pixelSize) {
            case .done(let result): deliver(result)
            case .evicted(let key, let file): self.fromCloud(url, pixelSize: pixelSize, key: key, file: file, request: request, deliver: deliver)
            }
        }
        request.onCancel { op.cancel() }
        queue.addOperation(op)
        return request
    }

    public static func cacheKey(path: String, modified: Date, size: Int, pixelSize: Int) -> String {
        let raw = "\(path)|\(modified.timeIntervalSince1970)|\(size)|\(pixelSize)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private enum Lookup {
        case done(Result<CGImage, DecodeError>)
        /// Not cached, and iCloud has evicted the file: `key` and `file` are where its thumbnail goes.
        case evicted(key: String, file: URL)
    }

    /// The caches, then a decode — unless the file is evicted, which is left to `fromCloud`.
    private func lookup(_ url: URL, pixelSize: Int) -> Lookup {
        // URL caches resource values per instance; a stale mtime would serve a stale thumbnail.
        var url = url
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate
        else { return .done(.failure(.unreadable)) }
        let key = Self.cacheKey(path: url.path, modified: modified, size: values.fileSize ?? 0, pixelSize: pixelSize)
        if let hit = memory.object(forKey: key as NSString) { return .done(.success(hit)) }

        let file = cacheDirectory.appendingPathComponent(key).appendingPathExtension("thumb")
        if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            remember(image, key)
            return .done(.success(image))
        }
        if cloud.isEvicted(url) { return .evicted(key: key, file: file) }
        return .done(decode(url, pixelSize: pixelSize, key: key, file: file))
    }

    /// Asks the cloud without holding a decode worker. With no stored thumbnail the file is decoded
    /// after all — downloading it — still off the workers.
    private func fromCloud(_ url: URL, pixelSize: Int, key: String, file: URL, request: ThumbnailRequest,
                           deliver: @escaping (Result<CGImage, DecodeError>) -> Void) {
        let cancel = cloud.thumbnail(url, maxPixelSize: pixelSize) { [weak self] image in
            guard let self, !request.isCancelled else { return }
            if let image {
                self.persist(image, to: file)
                self.remember(image, key)
                deliver(.success(image))
            } else {
                DispatchQueue.global(qos: .utility).async {
                    guard !request.isCancelled else { return }
                    deliver(self.decode(url, pixelSize: pixelSize, key: key, file: file))
                }
            }
        }
        request.onCancel(cancel)
    }

    private func decode(_ url: URL, pixelSize: Int, key: String, file: URL) -> Result<CGImage, DecodeError> {
        switch decoder.decode(url, maxPixelSize: pixelSize) {
        case .failure(let error):
            return .failure(error)
        case .success(let decoded):
            persist(decoded.cgImage, to: file)
            remember(decoded.cgImage, key)
            return .success(decoded.cgImage)
        }
    }

    private func remember(_ image: CGImage, _ key: String) {
        memory.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
    }

    /// JPEG when opaque (small); PNG when the thumbnail has transparency. Not HEIC: its encoder
    /// is missing on virtualised macOS (CI runners).
    private func persist(_ image: CGImage, to file: URL) {
        let opaque = [CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type = opaque ? UTType.jpeg : UTType.png
        let options: [CFString: Any] = opaque ? [kCGImageDestinationLossyCompressionQuality: 0.8] : [:]
        let temp = cacheDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, type.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { try? FileManager.default.removeItem(at: temp); return }
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.moveItem(at: temp, to: file)
    }
}

/// A pending `ThumbnailService` request. Once cancelled, its completion never runs.
public final class ThumbnailRequest {
    private let lock = NSLock()
    private var cancelled = false
    private var cancels: [() -> Void] = []

    public var isCancelled: Bool { lock.withLock { cancelled } }

    public func cancel() {
        let pending: [() -> Void] = lock.withLock {
            guard !cancelled else { return [] }
            cancelled = true
            defer { cancels = [] }
            return cancels
        }
        pending.forEach { $0() }
    }

    /// Runs `action` on cancel — at once if already cancelled.
    func onCancel(_ action: @escaping () -> Void) {
        let now: Bool = lock.withLock {
            if cancelled { return true }
            cancels.append(action)
            return false
        }
        if now { action() }
    }
}
