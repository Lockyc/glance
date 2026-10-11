import AppKit
@testable import glance
import GlanceCore
import UniformTypeIdentifiers
import XCTest

/// Files arriving or leaving must not disturb what the person is looking at.
final class FolderChangeTests: XCTestCase {
    private var dir: URL!
    private var model: FolderModel!
    private var controller: BrowserWindowController!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-change-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["b.png", "c.png", "d.png"] { write(name) }
        model = try FolderModel.load(folder: dir, current: dir.appendingPathComponent("b.png"))
        let thumbs = ThumbnailService(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)"))
        controller = BrowserWindowController(model: model, thumbnails: thumbs, startInGrid: false)
        spin { self.model.files.count == 3 }
    }

    override func tearDown() { controller.close() }

    private func write(_ name: String) {
        let ctx = CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
    }

    private func spin(_ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    func testZoomSurvivesAFileArriving() throws {
        let viewer = try XCTUnwrap(controller.window?.firstResponder as? ViewerView)
        spin { viewer.viewport != nil }
        viewer.actualSize(nil)
        XCTAssertEqual(viewer.viewport?.isFit, false)
        write("a.png")
        model.replaceFiles(try FolderModel.scan(dir))
        XCTAssertEqual(model.current?.lastPathComponent, "b.png")
        XCTAssertEqual(viewer.viewport?.isFit, false, "zoom reset by an unrelated file")
    }

    func testGridSelectionSurvivesAFileArriving() throws {
        controller.showGrid()
        let grid = try XCTUnwrap(controller.window?.firstResponder as? GridCollectionView)
        grid.selectionIndexPaths = [IndexPath(item: 2, section: 0)] // d.png, moved to by arrow keys
        write("a.png")
        model.replaceFiles(try FolderModel.scan(dir))
        XCTAssertEqual(grid.selectionIndexPaths, [IndexPath(item: 3, section: 0)], "selection should follow d.png")
    }
}
