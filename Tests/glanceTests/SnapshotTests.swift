import AppKit
@testable import glance
import GlanceCore
import XCTest

/// Off-screen PNGs of the comparison grid, its viewer and the hover previews, for looking at
/// rather than asserting on. Skipped unless GLANCE_SNAPSHOT_DIR is set (`just snapshot DIR`).
/// No window is ever ordered on screen or made key.
final class SnapshotTests: XCTestCase {
    private var out: URL!
    private var dir: URL!
    private var controllers: [BrowserWindowController] = []

    override func setUpWithError() throws {
        let path = ProcessInfo.processInfo.environment["GLANCE_SNAPSHOT_DIR"] ?? ""
        try XCTSkipIf(path.isEmpty, "run with `just snapshot DIR`")
        _ = NSApplication.shared
        out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("glance-snapshot-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { controllers.forEach { $0.close() } }

    // MARK: Fixtures

    private enum Shape: String, CaseIterable {
        case wide, tall, square
        var size: (Int, Int) {
            switch self {
            case .wide: (1600, 900)
            case .tall: (900, 1600)
            case .square: (1200, 1200)
            }
        }
    }

    private static let colors: [CGColor] = [
        CGColor(srgbRed: 0.85, green: 0.25, blue: 0.2, alpha: 1),
        CGColor(srgbRed: 0.2, green: 0.6, blue: 0.3, alpha: 1),
        CGColor(srgbRed: 0.2, green: 0.4, blue: 0.85, alpha: 1),
        CGColor(srgbRed: 0.9, green: 0.75, blue: 0.2, alpha: 1),
    ]

    /// One PNG per shot, in a folder per variant, filled in the variant's colour.
    private func fixture(_ variant: String, _ index: Int, _ shot: String, _ shape: Shape) throws -> URL {
        let folder = dir.appendingPathComponent(variant)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(shot).png")
        let (width, height) = shape.size
        writeTestPNG(to: url, width: width, height: height, color: Self.colors[index % Self.colors.count])
        return url
    }

    private func comparison(_ spec: [(String, [Shape])]) throws -> Comparison {
        Comparison(variants: try spec.enumerated().map { index, entry in
            Variant(label: entry.0, files: try entry.1.enumerated().map { shot, shape in
                try fixture(entry.0, index, "shot\(shot + 1)-\(shape.rawValue)", shape)
            })
        })
    }

    private func window(_ comparison: Comparison, size: NSSize, decoder: any ImageDecoding = ImageDecoder()) throws -> NSWindow {
        let model = FolderModel(folder: dir, files: comparison.files.map(FolderModel.canonical), current: nil, scope: .fixed)
        return try window(model: model, comparison: comparison, size: size, decoder: decoder)
    }

    /// Built as the app builds it, but never shown: the content size is set and laid out directly.
    private func window(model: FolderModel, comparison: Comparison?, size: NSSize,
                        decoder: any ImageDecoding = ImageDecoder()) throws -> NSWindow {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)")
        let controller = BrowserWindowController(model: model, thumbnails: ThumbnailService(decoder: decoder, cacheDirectory: cache),
                                                 startInGrid: true, comparison: comparison)
        controllers.append(controller)
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(size)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    // MARK: Driving

    /// Spins the run loop until `done`, failing after `timeout`.
    private func spin(until what: String, timeout: TimeInterval = 5, _ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() {
            guard Date() < deadline else { return XCTFail("timed out waiting for \(what)") }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func key(_ characters: String, _ keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    private func press(_ event: NSEvent, in window: NSWindow) { window.firstResponder?.keyDown(with: event) }

    private func mouseMoved(to view: NSView, in window: NSWindow) -> NSEvent {
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        return NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                  context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
    }

    private func comparisonGrid(_ window: NSWindow) throws -> (ComparisonGridViewController, ComparisonGridView) {
        let grid = try XCTUnwrap(descendants(of: window.contentView!, ComparisonGridView.self).first)
        let root = try XCTUnwrap(window.contentView?.subviews.first { $0.nextResponder is ComparisonGridViewController })
        return (try XCTUnwrap(root.nextResponder as? ComparisonGridViewController), grid)
    }

    private func thumbnailsLanded(_ grid: ComparisonGridView) -> Bool {
        grid.cellViews.allSatisfy { $0.url == nil || $0.image != nil }
    }

    private func previewShown(_ window: NSWindow) -> Bool {
        descendants(of: window.contentView!, HoverPreviewView.self).contains { !$0.isHidden && $0.alphaValue > 0.99 }
    }

    // MARK: Rendering

    private func snapshot(_ window: NSWindow, _ name: String) throws {
        let view = try XCTUnwrap(window.contentView)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent(name))
    }

    // MARK: Snapshots

    private func shotOneWindow(size: NSSize) throws -> (NSWindow, ComparisonGridViewController, ComparisonGridView) {
        let window = try window(try comparison([("a", [.wide, .tall]), ("b", [.wide]), ("c", [.square, .wide])]), size: size)
        let (controller, grid) = try comparisonGrid(window)
        spin(until: "the comparison thumbnails") { thumbnailsLanded(grid) }
        return (window, controller, grid)
    }

    func testComparisonGrid() throws {
        let (window, _, grid) = try shotOneWindow(size: NSSize(width: 1400, height: 900))
        XCTAssertEqual(grid.selection, Comparison.Cell(row: 0, column: 0))
        try snapshot(window, "comparison-grid.png")
    }

    /// Every cell still waiting on its thumbnail, so each shows its static.
    func testComparisonGridLoading() throws {
        let window = try window(try comparison([("a", [.wide, .tall]), ("b", [.wide]), ("c", [.square, .wide])]),
                                size: NSSize(width: 1400, height: 900), decoder: StalledDecoder())
        try snapshot(window, "comparison-loading.png")
    }

    /// Every cell's file unreadable, so each shows the can't-open glyph.
    func testComparisonGridFailed() throws {
        let window = try window(try comparison([("a", [.wide, .tall]), ("b", [.wide])]),
                                size: NSSize(width: 1400, height: 900), decoder: FailingDecoder())
        let (_, grid) = try comparisonGrid(window)
        spin(until: "the failed tiles") { grid.cellViews.allSatisfy { !$0.isLoading } }
        try snapshot(window, "comparison-failed.png")
    }

    func testComparisonGridOverflow() throws {
        let shapes: [Shape] = [.wide, .tall, .square, .wide, .tall, .square]
        let window = try window(try comparison(["a", "b", "c", "d"].map { ($0, shapes) }), size: NSSize(width: 900, height: 600))
        let (controller, grid) = try comparisonGrid(window)
        let scrollView = try XCTUnwrap(grid.enclosingScrollView)
        // Four default-size columns fit 900 pt; one zoom step makes them overflow sideways too.
        let key = "comparisonMinimumSide", stored = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(stored, forKey: key) }
        controller.zoomIn(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        spin(until: "the visible thumbnails") { thumbnailsLanded(grid) }
        let clip = scrollView.contentView
        let maxX = grid.frame.width - clip.bounds.width, maxY = grid.frame.height - clip.bounds.height
        XCTAssertGreaterThan(maxX, 0, "the grid overflows horizontally")
        XCTAssertGreaterThan(maxY, 0, "the grid overflows vertically")
        clip.scroll(to: NSPoint(x: maxX / 2, y: maxY / 2))
        scrollView.reflectScrolledClipView(clip)
        try snapshot(window, "comparison-grid-overflow.png")
    }

    func testComparisonViewer() throws {
        let (window, _, _) = try shotOneWindow(size: NSSize(width: 1400, height: 900))
        press(key("\r", 36), in: window)
        press(key(String(UnicodeScalar(NSRightArrowFunctionKey)!), 124), in: window)
        XCTAssertTrue(window.firstResponder is ViewerView)
        spin(until: "b's wide shot to decode") { window.title.hasSuffix("1600×900") && window.title.hasPrefix("b · ") }
        print("comparison-viewer.png window title: \(window.title)")
        try snapshot(window, "comparison-viewer.png")
    }

    func testComparisonHover() throws {
        let (window, controller, grid) = try shotOneWindow(size: NSSize(width: 900, height: 600))
        let target = grid.cellViews[0 * 3 + 1]
        controller.mouseMoved(with: mouseMoved(to: target, in: window))
        spin(until: "the comparison hover preview", timeout: HoverPreview.delay + 5) { previewShown(window) }
        try snapshot(window, "comparison-hover.png")
    }

    func testThumbnailHover() throws {
        for (index, shape) in Shape.allCases.enumerated() { _ = try fixture("folder", index, "\(index + 1)-\(shape.rawValue)", shape) }
        let model = try FolderModel.load(folder: dir.appendingPathComponent("folder"))
        let window = try window(model: model, comparison: nil, size: NSSize(width: 900, height: 600))
        spin(until: "the folder scan") { model.files.count == Shape.allCases.count }
        let collection = try XCTUnwrap(descendants(of: window.contentView!, GridCollectionView.self).first)
        collection.layoutSubtreeIfNeeded()
        spin(until: "the tile thumbnails") {
            let items = collection.visibleItems().compactMap { $0 as? ThumbnailItem }
            return items.count == Shape.allCases.count && items.allSatisfy { $0.image != nil }
        }
        let second = try XCTUnwrap(collection.item(at: IndexPath(item: 1, section: 0)))
        let root = try XCTUnwrap(window.contentView?.subviews.first { !($0 is ViewerView) })
        let controller = try XCTUnwrap(root.nextResponder as? GridViewController)
        controller.mouseMoved(with: mouseMoved(to: second.view, in: window))
        spin(until: "the thumbnail hover preview", timeout: HoverPreview.delay + 5) { previewShown(window) }
        try snapshot(window, "thumbnail-hover.png")
    }
}

/// Fails every file at once, so each cell shows the can't-open glyph.
private final class FailingDecoder: ImageDecoding {
    func decode(_ url: URL, maxPixelSize: Int) -> Result<DecodedImage, DecodeError> { .failure(.unreadable) }
}

/// Never delivers within a snapshot's lifetime, so the cells stay loading.
private final class StalledDecoder: ImageDecoding {
    func decode(_ url: URL, maxPixelSize: Int) -> Result<DecodedImage, DecodeError> {
        Thread.sleep(forTimeInterval: 2)
        return .failure(.unreadable)
    }
}
