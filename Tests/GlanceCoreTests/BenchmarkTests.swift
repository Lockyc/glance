@testable import GlanceCore
import XCTest

/// Latency targets from the spec. Skipped unless GLANCE_BENCH=1 (`just bench`) — CI runners
/// are too noisy to gate on wall-clock time.
final class BenchmarkTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GLANCE_BENCH"] == "1", "run with `just bench`")
    }

    private func median(_ runs: Int = 5, _ body: () -> Void) -> Double {
        body() // warm
        let times = (0..<runs).map { _ -> Double in
            let start = CFAbsoluteTimeGetCurrent()
            body()
            return CFAbsoluteTimeGetCurrent() - start
        }
        return times.sorted()[runs / 2]
    }

    func testScreenSizedDecodeOf12MegapixelJPEGUnder100ms() {
        let url = Fixtures.tempDir().appendingPathComponent("big.jpg")
        XCTAssertTrue(Fixtures.write(Fixtures.testImage(width: 4032, height: 3024), to: url, type: .jpeg))
        let t = median { _ = ImageDecoder().decode(url, maxPixelSize: 2880) }
        XCTAssertLessThan(t, 0.100, "median \(Int(t * 1000)) ms")
    }

    func testGridThumbnailDecodeUnder30ms() {
        let url = Fixtures.tempDir().appendingPathComponent("big.jpg")
        XCTAssertTrue(Fixtures.write(Fixtures.testImage(width: 4032, height: 3024), to: url, type: .jpeg))
        let t = median { _ = ImageDecoder().decode(url, maxPixelSize: 320) }
        XCTAssertLessThan(t, 0.030, "median \(Int(t * 1000)) ms")
    }

    func testScanOf5000FilesUnder300ms() {
        let dir = Fixtures.tempDir()
        Fixtures.touch((0..<5000).map { "IMG_\($0).jpg" }, in: dir)
        let t = median(3) { _ = try? FolderModel.scan(dir) }
        XCTAssertLessThan(t, 0.300, "median \(Int(t * 1000)) ms")
    }
}
