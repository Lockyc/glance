import AppKit
@testable import glance
import GlanceCore
import XCTest

final class FolderLoadingTests: XCTestCase {
    override func setUp() { _ = NSApplication.shared }

    /// The window opens on the one file it was given; the folder listing arrives from a background scan.
    func testWindowFillsInItsFolderAfterOpeningOnOneFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-load-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["a.jpg", "b.jpg", "c.jpg"] { FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data()) }
        let opened = dir.appendingPathComponent("b.jpg")
        let model = FolderModel(folder: dir, files: [FolderModel.canonical(opened)], current: opened)
        let thumbs = ThumbnailService(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)"))
        let controller = BrowserWindowController(model: model, thumbnails: thumbs, startInGrid: false)

        let deadline = Date().addingTimeInterval(2)
        while model.files.count < 3, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(model.files.map(\.lastPathComponent), ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertEqual(model.current?.lastPathComponent, "b.jpg")
        controller.close()
    }

    func testTilesSpinUntilTheirThumbnailLands() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-load-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = ["a.png", "b.png", "c.png"].map { dir.appendingPathComponent($0) }
        files.forEach { writeTestPNG(to: $0) }
        let model = FolderModel(folder: dir, files: files, current: nil, scope: .fixed)
        let thumbs = ThumbnailService(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)"))
        let grid = GridViewController(model: model, thumbnails: thumbs)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = grid.view
        grid.view.layoutSubtreeIfNeeded()
        let collection = try XCTUnwrap(descendants(of: grid.view, GridCollectionView.self).first)
        collection.layoutSubtreeIfNeeded()
        let items = collection.visibleItems().compactMap { $0 as? ThumbnailItem }
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy(\.isLoading))

        let deadline = Date().addingTimeInterval(5)
        while items.contains(where: { $0.image == nil }), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertFalse(items.contains(where: \.isLoading))
    }
}
