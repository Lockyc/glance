import GlanceCore
import XCTest

final class GeometryTests: XCTestCase {
    let large = Viewport.fit(imageSize: CGSize(width: 4000, height: 3000), viewSize: CGSize(width: 1000, height: 750), backingScale: 2)

    private func imagePoint(_ v: Viewport, at p: CGPoint) -> CGPoint {
        let k = v.scale / v.backingScale
        return CGPoint(x: (p.x - v.imageFrame.minX) / k, y: (p.y - v.imageFrame.minY) / k)
    }

    func testFitFillsViewForLargeImage() {
        XCTAssertEqual(large.scale, 0.5, accuracy: 1e-9)
        XCTAssertEqual(large.imageFrame, CGRect(x: 0, y: 0, width: 1000, height: 750))
        XCTAssertTrue(large.isFit)
    }

    func testFitNeverUpscalesSmallImage() {
        let v = Viewport.fit(imageSize: CGSize(width: 100, height: 100), viewSize: CGSize(width: 1000, height: 750), backingScale: 2)
        XCTAssertEqual(v.scale, 1)
        XCTAssertEqual(v.imageFrame, CGRect(x: 475, y: 350, width: 50, height: 50))
    }

    func testZoomKeepsPointUnderCursor() {
        let p = CGPoint(x: 250, y: 200)
        let before = imagePoint(large, at: p)
        let zoomed = large.zoomed(to: 1, about: p)
        let after = imagePoint(zoomed, at: p)
        XCTAssertEqual(before.x, after.x, accuracy: 0.5)
        XCTAssertEqual(before.y, after.y, accuracy: 0.5)
        XCTAssertFalse(zoomed.isFit)
    }

    func testZoomClampsBetweenFitAndMax() {
        XCTAssertEqual(large.zoomed(to: 0.01, about: .zero).scale, large.fitScale, accuracy: 1e-9)
        XCTAssertTrue(large.zoomed(to: 0.01, about: .zero).isFit)
        XCTAssertEqual(large.zoomed(to: 1000, about: .zero).scale, Viewport.maxScale)
    }

    func testPanStopsAtImageEdges() {
        let v = large.zoomed(to: 1, about: CGPoint(x: 500, y: 375))
        XCTAssertEqual(v.panned(by: CGSize(width: 100_000, height: 0)).imageFrame.minX, 0, accuracy: 1e-6)
        XCTAssertEqual(v.panned(by: CGSize(width: -100_000, height: 0)).imageFrame.maxX, 1000, accuracy: 1e-6)
        XCTAssertEqual(v.panned(by: CGSize(width: 0, height: 100_000)).imageFrame.minY, 0, accuracy: 1e-6)
    }

    func testPanDoesNothingWhenImageFits() {
        XCTAssertEqual(large.panned(by: CGSize(width: 50, height: 50)).imageFrame, large.imageFrame)
    }

    func testResizeRefitsWhenFitAndClampsWhenZoomed() {
        let refit = large.resized(to: CGSize(width: 500, height: 375), backingScale: 2)
        XCTAssertEqual(refit.imageFrame, CGRect(x: 0, y: 0, width: 500, height: 375))
        let zoomed = large.zoomed(to: 2, about: CGPoint(x: 500, y: 375)).resized(to: CGSize(width: 500, height: 375), backingScale: 2)
        XCTAssertEqual(zoomed.scale, 2)
        XCTAssertLessThanOrEqual(zoomed.imageFrame.minX, 0)
        XCTAssertGreaterThanOrEqual(zoomed.imageFrame.maxX, 500)
    }

    func testTitle() {
        XCTAssertEqual(ViewerTitle.text(fileName: "a.jpg", index: 11, count: 340, pixelSize: CGSize(width: 4032, height: 3024)),
                       "a.jpg — 12 / 340 — 4032×3024")
        XCTAssertEqual(ViewerTitle.text(fileName: "a.jpg", index: 0, count: 1, pixelSize: nil), "a.jpg — 1 / 1")
    }

    func testHoverSideIsAlwaysLargerThanTile() {
        XCTAssertEqual(HoverPreview.side(tileSide: 160), 400)
        XCTAssertEqual(HoverPreview.side(tileSide: 320), 480)
        for tile in stride(from: HoverPreview.tileSideRange.lowerBound, through: HoverPreview.tileSideRange.upperBound, by: 16) {
            XCTAssertGreaterThan(HoverPreview.side(tileSide: tile), tile)
        }
    }

    func testHoverFrameCentresOnTileAndKeepsAspect() {
        let bounds = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        let tile = CGRect(x: 900, y: 900, width: 160, height: 160)
        let f = HoverPreview.frame(around: tile, imageSize: CGSize(width: 400, height: 200), side: 400, bounds: bounds)
        XCTAssertEqual(f, CGRect(x: 780, y: 880, width: 400, height: 200))
    }

    func testHoverFrameClampsInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let corner = CGRect(x: 0, y: 0, width: 160, height: 160)
        let f = HoverPreview.frame(around: corner, imageSize: CGSize(width: 1, height: 1), side: 400, bounds: bounds)
        XCTAssertEqual(f.origin, .zero)
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 200)
        let shrunk = HoverPreview.frame(around: corner, imageSize: CGSize(width: 1, height: 1), side: 400, bounds: tiny)
        XCTAssertEqual(shrunk.size, CGSize(width: 200, height: 200))
        XCTAssertTrue(tiny.contains(shrunk))
    }
}
