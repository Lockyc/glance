import AppKit
@testable import glance
import GlanceCore
import XCTest

final class ViewerClickTests: XCTestCase {
    private func viewer() -> ViewerView {
        _ = NSApplication.shared
        let view = ViewerView(frame: NSRect(x: 0, y: 0, width: 1000, height: 750))
        let ctx = CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let url = URL(fileURLWithPath: "/x/big.png")
        view.show(.success(DecodedImage(url: url, cgImage: ctx.makeImage()!, pixelSize: CGSize(width: 4000, height: 3000), isAnimated: false)), for: url)
        return view
    }

    private func click(_ count: Int) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 500, y: 375), modifierFlags: [], timestamp: 0,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
    }

    func testDoubleClickInTheViewerTogglesActualSize() {
        let v = viewer()
        v.mouseDown(with: click(1))
        v.mouseDown(with: click(2))
        XCTAssertEqual(v.viewport?.isFit, false)
    }

    /// A double-click on a grid tile opens on the first click; the second lands on the viewer.
    func testSecondClickOfADoubleClickThatBeganInTheGridDoesNotZoom() {
        let v = viewer()
        v.mouseDown(with: click(1)) // an earlier click in the viewer, before going to the grid
        v.isHidden = true
        v.isHidden = false
        v.mouseDown(with: click(2))
        XCTAssertEqual(v.viewport?.isFit, true)
    }

    func testAFittedImageDragsOutAsItsFileAZoomedOneDoesNot() throws {
        let v = viewer()
        let item = try XCTUnwrap(v.dragOutItem())
        let written = try XCTUnwrap(item.item as? NSPasteboardItem)
        XCTAssertEqual(written.string(forType: .fileURL), URL(fileURLWithPath: "/x/big.png").absoluteString)
        v.actualSize(nil)
        XCTAssertNil(v.dragOutItem(), "a zoomed image pans instead")
    }

    /// A zoom's pending full-detail request belongs to the image it was made for.
    func testShowingAnotherImageDropsThePendingResolutionRequest() {
        _ = NSApplication.shared
        let v = ViewerView(frame: NSRect(x: 0, y: 0, width: 1000, height: 750))
        func image(_ name: String, bitmapWidth: Int) -> (URL, DecodedImage) {
            let ctx = CGContext(data: nil, width: bitmapWidth, height: bitmapWidth * 3 / 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let url = URL(fileURLWithPath: "/x/\(name)")
            return (url, DecodedImage(url: url, cgImage: ctx.makeImage()!, pixelSize: CGSize(width: 4000, height: 3000), isAnimated: false))
        }
        var requested: [URL] = []
        v.onNeedsResolution = { url, _ in requested.append(url) }
        var pending: [DispatchWorkItem] = []
        v.afterZoomSettles = { pending.append($0) }
        // A is a screen-size decode that zooming outgrows; B is already at full detail, so it asks for nothing.
        let (a, decodedA) = image("a.png", bitmapWidth: 400), (b, decodedB) = image("b.png", bitmapWidth: 4000)
        v.show(.success(decodedA), for: a)
        v.actualSize(nil)
        XCTAssertTrue(pending.contains { !$0.isCancelled }, "the zoom armed no request for A")
        v.show(.success(decodedB), for: b)
        // The delay elapses: as on a queue, a cancelled item does not run.
        pending.filter { !$0.isCancelled }.forEach { $0.perform() }
        XCTAssertFalse(requested.contains(a))
    }
}
