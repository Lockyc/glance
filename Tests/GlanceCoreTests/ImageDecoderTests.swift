@testable import GlanceCore
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class ImageDecoderTests: XCTestCase {
    let decoder = ImageDecoder()
    let dir = Fixtures.tempDir()

    /// Every format ImageIO can *write* on this machine round-trips through the decoder.
    func testDecodesEveryWritableSupportedFormat() {
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).compactMap(UTType.init)
        let candidates = writable.filter { ImageTypes.supported.contains($0) }
        XCTAssertGreaterThan(candidates.count, 5)
        for type in candidates {
            let url = dir.appendingPathComponent("x").appendingPathExtension(type.preferredFilenameExtension ?? "img")
            guard Fixtures.write(Fixtures.testImage(width: 64, height: 48), to: url, type: type) else { continue }
            switch decoder.decode(url, maxPixelSize: 1000) {
            case .success(let image):
                XCTAssertEqual(image.pixelSize, CGSize(width: 64, height: 48), type.identifier)
                XCTAssertEqual(image.cgImage.width, 64, "never upscaled: \(type.identifier)")
            case .failure:
                XCTFail("failed to decode \(type.identifier)")
            }
        }
    }

    func testDownsamplesToMaxPixelSize() throws {
        let url = dir.appendingPathComponent("big.jpg")
        Fixtures.write(Fixtures.testImage(width: 2000, height: 1000), to: url, type: .jpeg)
        let image = try decoder.decode(url, maxPixelSize: 500).get()
        XCTAssertEqual(image.cgImage.width, 500)
        XCTAssertEqual(image.cgImage.height, 250)
        XCTAssertEqual(image.pixelSize, CGSize(width: 2000, height: 1000))
    }

    func testAppliesEXIFOrientation() throws {
        let url = dir.appendingPathComponent("rotated.jpg")
        Fixtures.write(Fixtures.testImage(width: 64, height: 48), to: url, type: .jpeg, properties: [kCGImagePropertyOrientation: 6])
        let image = try decoder.decode(url, maxPixelSize: 1000).get()
        XCTAssertEqual(image.pixelSize, CGSize(width: 48, height: 64))
        XCTAssertEqual(image.cgImage.width, 48)
        XCTAssertEqual(image.cgImage.height, 64)
    }

    func testAnimatedGIFIsFlaggedAndStillGIFIsNot() throws {
        let animated = dir.appendingPathComponent("anim.gif")
        Fixtures.writeAnimatedGIF(to: animated, frames: 3)
        XCTAssertTrue(try decoder.decode(animated, maxPixelSize: 100).get().isAnimated)

        let still = dir.appendingPathComponent("still.gif")
        Fixtures.write(Fixtures.testImage(width: 8, height: 8), to: still, type: .gif)
        XCTAssertFalse(try decoder.decode(still, maxPixelSize: 100).get().isAnimated)
    }

    func testRendersSVGAtRequestedSize() throws {
        let url = dir.appendingPathComponent("v.svg")
        Fixtures.writeSVG(to: url)
        let image = try decoder.decode(url, maxPixelSize: 400).get()
        XCTAssertEqual(image.pixelSize, CGSize(width: 40, height: 20))
        XCTAssertTrue(image.isVector)
        XCTAssertEqual(image.cgImage.width, 400)
        XCTAssertEqual(image.cgImage.height, 200)
    }

    func testCorruptZeroByteAndTruncatedFilesFailCleanly() throws {
        let zero = dir.appendingPathComponent("zero.png")
        FileManager.default.createFile(atPath: zero.path, contents: Data())
        XCTAssertEqual(decoder.decode(zero, maxPixelSize: 100).failureValue, .unreadable)

        let garbage = dir.appendingPathComponent("garbage.jpg")
        FileManager.default.createFile(atPath: garbage.path, contents: Data((0..<4096).map { UInt8($0 % 251) }))
        XCTAssertEqual(decoder.decode(garbage, maxPixelSize: 100).failureValue, .unreadable)

        let full = dir.appendingPathComponent("full.jpg")
        Fixtures.write(Fixtures.testImage(width: 400, height: 300), to: full, type: .jpeg)
        let bytes = try Data(contentsOf: full)
        let truncated = dir.appendingPathComponent("truncated.jpg")
        try bytes.prefix(bytes.count / 2).write(to: truncated)
        _ = decoder.decode(truncated, maxPixelSize: 100) // success (partial) or failure — must not crash

        let badSVG = dir.appendingPathComponent("bad.svg")
        try "<svg".write(to: badSVG, atomically: true, encoding: .utf8)
        XCTAssertEqual(decoder.decode(badSVG, maxPixelSize: 100).failureValue, .unreadable)

        XCTAssertEqual(decoder.decode(dir.appendingPathComponent("missing.jpg"), maxPixelSize: 100).failureValue, .unreadable)
    }
}

extension Result {
    var failureValue: Failure? { if case .failure(let e) = self { return e } else { return nil } }
}
