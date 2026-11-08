import CoreGraphics
import Foundation
import QuickLookThumbnailing

/// Thumbnails for files iCloud has evicted (dataless). Reading an evicted file's bytes downloads
/// all of it, and while iCloud's sync is backed up that download — or any fetch of the file — can
/// take minutes. So an evicted file never goes through the decode workers: its thumbnail is asked
/// for here, asynchronously, and the tile waits without holding up any other.
public protocol CloudThumbnailing {
    func isEvicted(_ url: URL) -> Bool
    /// Answers once, on any thread, with `nil` when there is no thumbnail to be had. Returns a
    /// cancel, after which `completion` may still run but its answer is unwanted.
    func thumbnail(_ url: URL, maxPixelSize: Int, completion: @escaping (CGImage?) -> Void) -> () -> Void
}

/// Quick Look serves iCloud's stored thumbnail of an evicted file and leaves the file evicted.
public struct QuickLookCloudThumbnails: CloudThumbnailing {
    public init() {}

    public func isEvicted(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    public func thumbnail(_ url: URL, maxPixelSize: Int, completion: @escaping (CGImage?) -> Void) -> () -> Void {
        let side = CGFloat(maxPixelSize)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 1,
                                                   representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in completion(representation?.cgImage) }
        return { QLThumbnailGenerator.shared.cancel(request) }
    }
}
