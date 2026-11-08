@testable import GlanceCore
import UniformTypeIdentifiers
import XCTest

final class CountingDecoder: ImageDecoding {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    func decode(_ url: URL, maxPixelSize: Int) -> Result<DecodedImage, DecodeError> {
        lock.withLock { _count += 1 }
        return ImageDecoder().decode(url, maxPixelSize: maxPixelSize)
    }
}

/// Evicted files: every one when `evicted`, else those named `cloud*`. A `nil` `image` with
/// `hangs` never answers, as iCloud does while its sync is backed up.
final class FakeCloud: CloudThumbnailing {
    private let lock = NSLock()
    private var _asked = 0
    private var _cancelled = 0
    var asked: Int { lock.withLock { _asked } }
    var cancelled: Int { lock.withLock { _cancelled } }
    let evicted: Bool
    let image: CGImage?
    let hangs: Bool
    init(evicted: Bool, image: CGImage?, hangs: Bool = false) { self.evicted = evicted; self.image = image; self.hangs = hangs }
    func isEvicted(_ url: URL) -> Bool { evicted || url.lastPathComponent.hasPrefix("cloud") }
    func thumbnail(_ url: URL, maxPixelSize: Int, completion: @escaping (CGImage?) -> Void) -> () -> Void {
        lock.withLock { _asked += 1 }
        if !hangs { DispatchQueue.global().async { [image] in completion(image) } }
        return { [weak self] in self?.lock.withLock { self?._cancelled += 1 } }
    }
}

final class ThumbnailServiceTests: XCTestCase {
    let images = Fixtures.tempDir()
    let cache = Fixtures.tempDir()

    private func thumbnail(_ service: ThumbnailService, _ url: URL, _ px: Int) -> Result<CGImage, DecodeError> {
        let done = expectation(description: "thumb")
        var out: Result<CGImage, DecodeError>!
        service.request(url, pixelSize: px) { out = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return out
    }

    private func cacheFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)) ?? []
    }

    func testCacheKeyVariesWithEveryInput() {
        let date = Date(timeIntervalSince1970: 1000)
        let base = ThumbnailService.cacheKey(path: "/a.jpg", modified: date, size: 10, pixelSize: 320)
        XCTAssertNotEqual(base, ThumbnailService.cacheKey(path: "/b.jpg", modified: date, size: 10, pixelSize: 320))
        XCTAssertNotEqual(base, ThumbnailService.cacheKey(path: "/a.jpg", modified: date.addingTimeInterval(1), size: 10, pixelSize: 320))
        XCTAssertNotEqual(base, ThumbnailService.cacheKey(path: "/a.jpg", modified: date, size: 11, pixelSize: 320))
        XCTAssertNotEqual(base, ThumbnailService.cacheKey(path: "/a.jpg", modified: date, size: 10, pixelSize: 640))
    }

    func testThumbnailIsBoundedAndPersistedToDisk() throws {
        let url = images.appendingPathComponent("p.png")
        Fixtures.write(Fixtures.testImage(width: 400, height: 300), to: url, type: .png)
        let image = try thumbnail(ThumbnailService(cacheDirectory: cache), url, 100).get()
        XCTAssertEqual(max(image.width, image.height), 100)
        XCTAssertEqual(cacheFiles().count, 1)
    }

    func testFreshServiceServesFromDiskWithoutDecoding() throws {
        let url = images.appendingPathComponent("p.png")
        Fixtures.write(Fixtures.testImage(width: 400, height: 300), to: url, type: .png)
        _ = try thumbnail(ThumbnailService(cacheDirectory: cache), url, 100).get()
        let decoder = CountingDecoder()
        _ = try thumbnail(ThumbnailService(decoder: decoder, cacheDirectory: cache), url, 100).get()
        XCTAssertEqual(decoder.count, 0)
    }

    func testModifiedFileIsRegenerated() throws {
        let url = images.appendingPathComponent("p.png")
        Fixtures.write(Fixtures.testImage(width: 400, height: 300), to: url, type: .png)
        let decoder = CountingDecoder()
        let service = ThumbnailService(decoder: decoder, cacheDirectory: cache)
        _ = try thumbnail(service, url, 100).get()
        Fixtures.write(Fixtures.testImage(width: 300, height: 400), to: url, type: .png)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        let image = try thumbnail(service, url, 100).get()
        XCTAssertEqual(decoder.count, 2)
        XCTAssertEqual(image.height, 100)
    }

    func testEvictedFileTakesItsThumbnailFromTheCloudWithoutDecoding() throws {
        let url = images.appendingPathComponent("p.png")
        Fixtures.write(Fixtures.testImage(width: 400, height: 300), to: url, type: .png)
        let decoder = CountingDecoder()
        let cloud = FakeCloud(evicted: true, image: Fixtures.testImage(width: 100, height: 75))
        let image = try thumbnail(ThumbnailService(decoder: decoder, cloud: cloud, cacheDirectory: cache), url, 100).get()
        XCTAssertEqual(decoder.count, 0, "an evicted file was read, which downloads it")
        XCTAssertEqual(image.width, 100)
        XCTAssertEqual(cacheFiles().count, 1)
    }

    func testEvictedFileWithNoCloudThumbnailIsDecoded() throws {
        let url = images.appendingPathComponent("p.png")
        Fixtures.write(Fixtures.testImage(width: 400, height: 300), to: url, type: .png)
        let decoder = CountingDecoder()
        let service = ThumbnailService(decoder: decoder, cloud: FakeCloud(evicted: true, image: nil), cacheDirectory: cache)
        _ = try thumbnail(service, url, 100).get()
        XCTAssertEqual(decoder.count, 1)
    }

    func testLocalFileNeverAsksTheCloud() throws {
        let url = images.appendingPathComponent("p.png")
        Fixtures.write(Fixtures.testImage(width: 400, height: 300), to: url, type: .png)
        let cloud = FakeCloud(evicted: false, image: Fixtures.testImage(width: 10, height: 10))
        let image = try thumbnail(ThumbnailService(cloud: cloud, cacheDirectory: cache), url, 100).get()
        XCTAssertEqual(image.width, 100)
        XCTAssertEqual(cloud.asked, 0)
    }

    func testLocalFileIsNotHeldUpByEvictedOnesThatNeverArrive() throws {
        let local = images.appendingPathComponent("p.png")
        Fixtures.write(Fixtures.testImage(width: 400, height: 300), to: local, type: .png)
        let service = ThumbnailService(cloud: FakeCloud(evicted: false, image: nil, hangs: true), cacheDirectory: cache)
        for i in 0..<64 {
            let url = images.appendingPathComponent("cloud\(i).png")
            Fixtures.write(Fixtures.testImage(width: 40, height: 30), to: url, type: .png)
            service.request(url, pixelSize: 100) { _ in XCTFail("a hung cloud thumbnail completed") }
        }
        XCTAssertEqual(try thumbnail(service, local, 100).get().width, 100)
    }

    func testCancellingAnEvictedRequestCancelsItsCloudThumbnail() throws {
        let url = images.appendingPathComponent("cloud.png")
        Fixtures.write(Fixtures.testImage(width: 40, height: 30), to: url, type: .png)
        let cloud = FakeCloud(evicted: false, image: nil, hangs: true)
        let service = ThumbnailService(cloud: cloud, cacheDirectory: cache)
        let request = service.request(url, pixelSize: 100) { _ in XCTFail("cancelled request completed") }
        let deadline = Date().addingTimeInterval(5)
        while cloud.asked == 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        request.cancel()
        XCTAssertEqual(cloud.cancelled, 1)
    }

    func testFailuresAreNotCachedToDisk() {
        let url = images.appendingPathComponent("bad.jpg")
        FileManager.default.createFile(atPath: url.path, contents: Data("nope".utf8))
        XCTAssertEqual(thumbnail(ThumbnailService(cacheDirectory: cache), url, 100).failureValue, .unreadable)
        XCTAssertEqual(cacheFiles().count, 0)
    }
}
