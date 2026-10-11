@testable import GlanceCore
import XCTest

final class FakeDecoder: ImageDecoding {
    private let lock = NSLock()
    private var _calls: [URL] = []
    var delay: TimeInterval = 0
    var calls: [URL] { lock.withLock { _calls } }

    func decode(_ url: URL, maxPixelSize: Int) -> Result<DecodedImage, DecodeError> {
        lock.withLock { _calls.append(url) }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return .success(DecodedImage(url: url, cgImage: Fixtures.testImage(width: 4, height: 4),
                                     pixelSize: CGSize(width: 4, height: 4), isAnimated: false))
    }
}

final class DecodeCacheTests: XCTestCase {
    let files = (0..<20).map { URL(fileURLWithPath: "/f/\($0).jpg") }

    private func waitForDecodes(_ cache: DecodeCache, _ count: Int, delivered: ((URL) -> Void)? = nil) {
        let done = expectation(description: "decoded")
        done.expectedFulfillmentCount = count
        cache.onDecoded = { url, _ in delivered?(url); done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testWindowOrderIsCurrentThenAlternatingNeighboursWrapped() {
        XCTAssertEqual(DecodeCache.windowOrder(index: 5, count: 10, radius: 2), [5, 6, 4, 7, 3])
        XCTAssertEqual(DecodeCache.windowOrder(index: 0, count: 10, radius: 2), [0, 1, 9, 2, 8])
        XCTAssertEqual(DecodeCache.windowOrder(index: 0, count: 3, radius: 2), [0, 1, 2])
        XCTAssertEqual(DecodeCache.windowOrder(index: 0, count: 1, radius: 2), [0])
    }

    func testFocusDecodesWindowStartingWithCurrent() {
        let decoder = FakeDecoder()
        let cache = DecodeCache(decoder: decoder, maxPixelSize: 100)
        cache.focus(on: 5, in: files)
        waitForDecodes(cache, 5)
        XCTAssertEqual(decoder.calls.first, files[5])
        for i in 3...7 { XCTAssertNotNil(cache.result(for: files[i]), "\(i)") }
        XCTAssertNil(cache.result(for: files[8]))
    }

    func testMovingEvictsOutsideWindowAndReusesOverlap() {
        let decoder = FakeDecoder()
        let cache = DecodeCache(decoder: decoder, maxPixelSize: 100)
        cache.focus(on: 5, in: files)
        waitForDecodes(cache, 5)
        cache.focus(on: 7, in: files) // window 5...9: 5,6,7 already cached
        waitForDecodes(cache, 2)
        XCTAssertNil(cache.result(for: files[3]))
        XCTAssertNil(cache.result(for: files[4]))
        XCTAssertEqual(decoder.calls.count, 7)
    }

    func testResultsForFilesThatLeftTheWindowAreDiscarded() {
        let decoder = FakeDecoder()
        decoder.delay = 0.2
        let cache = DecodeCache(decoder: decoder, maxPixelSize: 100)
        cache.focus(on: 0, in: files)
        cache.focus(on: 10, in: files) // user held → past the first window
        var delivered: [URL] = []
        waitForDecodes(cache, 5) { delivered.append($0) }
        let drained = expectation(description: "drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(Set(delivered), Set([8, 9, 10, 11, 12].map { files[$0] }))
        XCTAssertNil(cache.result(for: files[0]))
    }

    func testEmptyFolderClearsEverything() {
        let cache = DecodeCache(decoder: FakeDecoder(), maxPixelSize: 100)
        cache.focus(on: 0, in: files)
        waitForDecodes(cache, 5)
        cache.focus(on: 0, in: [])
        XCTAssertNil(cache.result(for: files[0]))
    }
}
