import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Grid thumbnails and hover previews: memory cache (evicts under pressure), then a disk
/// cache keyed by path + mtime + size + pixel size, then a real decode. Failures are never
/// cached, so a file still being copied in gets a fresh attempt on the next request.
public final class ThumbnailService {
    public static let defaultCacheDirectory = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("glance/thumbnails", isDirectory: true)

    private let decoder: any ImageDecoding
    private let cacheDirectory: URL
    private let memory = NSCache<NSString, CGImage>()
    private let queue = OperationQueue()

    public init(decoder: any ImageDecoding = ImageDecoder(), cacheDirectory: URL = defaultCacheDirectory) {
        self.decoder = decoder
        self.cacheDirectory = cacheDirectory
        memory.totalCostLimit = 256 << 20
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
        queue.qualityOfService = .userInitiated
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    @discardableResult
    public func request(_ url: URL, pixelSize: Int, completion: @escaping (Result<CGImage, DecodeError>) -> Void) -> Operation {
        let op = BlockOperation()
        op.addExecutionBlock { [weak self, weak op] in
            guard let self, let op, !op.isCancelled else { return }
            let result = self.thumbnail(url, pixelSize: pixelSize)
            DispatchQueue.main.async { if !op.isCancelled { completion(result) } }
        }
        queue.addOperation(op)
        return op
    }

    public static func cacheKey(path: String, modified: Date, size: Int, pixelSize: Int) -> String {
        let raw = "\(path)|\(modified.timeIntervalSince1970)|\(size)|\(pixelSize)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func thumbnail(_ url: URL, pixelSize: Int) -> Result<CGImage, DecodeError> {
        // URL caches resource values per instance; a stale mtime would serve a stale thumbnail.
        var url = url
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate
        else { return .failure(.unreadable) }
        let key = Self.cacheKey(path: url.path, modified: modified, size: values.fileSize ?? 0, pixelSize: pixelSize)
        if let hit = memory.object(forKey: key as NSString) { return .success(hit) }

        let file = cacheDirectory.appendingPathComponent(key).appendingPathExtension("thumb")
        if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            remember(image, key)
            return .success(image)
        }

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
