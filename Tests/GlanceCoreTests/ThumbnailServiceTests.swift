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

    func testFailuresAreNotCachedToDisk() {
        let url = images.appendingPathComponent("bad.jpg")
        FileManager.default.createFile(atPath: url.path, contents: Data("nope".utf8))
        XCTAssertEqual(thumbnail(ThumbnailService(cacheDirectory: cache), url, 100).failureValue, .unreadable)
        XCTAssertEqual(cacheFiles().count, 0)
    }
}
