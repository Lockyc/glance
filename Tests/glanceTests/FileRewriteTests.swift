import AppKit
@testable import glance
import GlanceCore
import XCTest

/// A file re-saved in place redraws wherever it shows — viewer, grid tile, comparison cell — in
/// folder, set and comparison windows alike.
final class FileRewriteTests: XCTestCase {
    private var dir: URL!
    private var controller: BrowserWindowController?

    override func setUpWithError() throws {
        _ = NSApplication.shared
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-rewrite-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["a.png", "b.png", "c.png"] { writeTestPNG(to: url(name), width: 400, height: 300, color: .black) }
    }

    override func tearDown() { controller?.close() }

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    private func thumbnails() -> ThumbnailService {
        ThumbnailService(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)"))
    }

    @discardableResult
    private func spin(_ seconds: TimeInterval = 3, until done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return done()
    }

    private func open(_ model: FolderModel, grid: Bool = false, comparison: Comparison? = nil) throws -> BrowserWindowController {
        let made = BrowserWindowController(model: model, thumbnails: thumbnails(), startInGrid: grid, comparison: comparison)
        controller = made
        made.window?.layoutIfNeeded()
        return made
    }

    private func viewer(_ controller: BrowserWindowController) throws -> ViewerView {
        try XCTUnwrap(descendants(of: try XCTUnwrap(controller.window?.contentView), ViewerView.self).first)
    }

    private func folderWindow(grid: Bool = false) throws -> (BrowserWindowController, FolderModel) {
        let model = try FolderModel.load(folder: dir, current: url("b.png"))
        let made = try open(model, grid: grid)
        spin { model.files.count == 3 }
        return (made, model)
    }

    func testViewerRedrawsAReSavedFileAndKeepsItsZoom() throws {
        let (controller, _) = try folderWindow()
        let viewer = try viewer(controller)
        XCTAssertTrue(spin { viewer.image != nil })
        let before = try XCTUnwrap(viewer.image?.cgImage)
        viewer.zoomIn(nil)
        let zoomed = viewer.viewport?.scale
        XCTAssertEqual(viewer.viewport?.isFit, false)

        writeTestPNG(to: url("b.png"), width: 400, height: 300, color: .white)
        XCTAssertTrue(spin { viewer.image.map { $0.cgImage !== before } ?? false }, "re-saved image never redrawn")
        XCTAssertEqual(viewer.viewport?.scale, zoomed, "a re-save of the same size reset the zoom")
    }

    func testViewerFitsAReSavedFileOfANewSize() throws {
        let (controller, _) = try folderWindow()
        let viewer = try viewer(controller)
        XCTAssertTrue(spin { viewer.image != nil })
        viewer.zoomIn(nil)

        writeTestPNG(to: url("b.png"), width: 200, height: 500, color: .white)
        XCTAssertTrue(spin { viewer.viewport?.imageSize == CGSize(width: 200, height: 500) })
        XCTAssertEqual(viewer.viewport?.isFit, true)
    }

    func testGridTileRedrawsAReSavedFile() throws {
        let (controller, _) = try folderWindow(grid: true)
        let grid = try XCTUnwrap(controller.window?.firstResponder as? GridCollectionView)
        func tile() -> ThumbnailItem? { grid.item(at: IndexPath(item: 1, section: 0)) as? ThumbnailItem }
        XCTAssertTrue(spin { tile()?.image != nil })
        let before = try XCTUnwrap(tile()?.image)

        writeTestPNG(to: url("b.png"), width: 400, height: 300, color: .white)
        XCTAssertTrue(spin { tile()?.image.map { $0 !== before } ?? false }, "visible tile kept the old thumbnail")
    }

    func testSetWindowRedrawsAReSavedFile() throws {
        let model = FolderModel(folder: dir, files: [url("c.png"), url("a.png")], current: nil, scope: .fixed)
        let controller = try open(model)
        let viewer = try viewer(controller)
        XCTAssertTrue(spin { viewer.image != nil })
        let before = try XCTUnwrap(viewer.image?.cgImage)

        writeTestPNG(to: url("c.png"), width: 400, height: 300, color: .white)
        XCTAssertTrue(spin { viewer.image.map { $0.cgImage !== before } ?? false }, "set window never redrew")
        XCTAssertEqual(model.files, [url("c.png"), url("a.png")], "a set window was relisted")
    }

    func testComparisonCellRedrawsAReSavedFile() throws {
        let comparison = Comparison(variants: [Variant(label: "a", files: [url("a.png")]), Variant(label: "b", files: [url("b.png")])])
        let model = FolderModel(folder: dir, files: comparison.files.map(FolderModel.canonical), current: nil, scope: .fixed)
        let controller = try open(model, grid: true, comparison: comparison)
        let cell = try XCTUnwrap(descendants(of: try XCTUnwrap(controller.window?.contentView), ComparisonCellView.self)
            .first { $0.url?.lastPathComponent == "b.png" })
        XCTAssertTrue(spin { cell.image != nil })
        let before = try XCTUnwrap(cell.image)

        writeTestPNG(to: url("b.png"), width: 400, height: 300, color: .white)
        XCTAssertTrue(spin { cell.image.map { $0 !== before } ?? false }, "comparison cell kept the old thumbnail")
    }
}
