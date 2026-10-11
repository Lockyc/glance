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
}
