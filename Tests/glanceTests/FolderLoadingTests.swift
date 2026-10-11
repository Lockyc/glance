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
}
