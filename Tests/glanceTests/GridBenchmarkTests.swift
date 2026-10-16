import AppKit
@testable import glance
import GlanceCore
import XCTest

/// Skipped unless GLANCE_BENCH=1 (`just bench`) — CI runners are too noisy to gate on wall-clock time.
final class GridBenchmarkTests: XCTestCase {
    func testLayoutOf25000TilesIn36MonthsUnder250ms() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GLANCE_BENCH"] == "1", "run with `just bench`")
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: "/nonexistent-glance-bench")
        let files = (0..<25_000).map { dir.appendingPathComponent("s\($0).png") }
        let dates = (0..<25_000).map { Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 3_780) } // ~36 months
        let model = FolderModel(folder: dir, files: files, current: nil, scope: .tree(excluded: []), dates: dates)
        let thumbs = ThumbnailService(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("glance-thumbs-\(UUID().uuidString)"))
        let grid = GridViewController(model: model, thumbnails: thumbs)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = grid.view
        grid.view.layoutSubtreeIfNeeded()
        var times: [Double] = []
        for _ in 0..<3 {
            let start = CFAbsoluteTimeGetCurrent()
            grid.reload()
            grid.view.layoutSubtreeIfNeeded()
            times.append(CFAbsoluteTimeGetCurrent() - start)
        }
        let median = times.sorted()[1]
        XCTAssertLessThan(median, 0.250, "median \(Int(median * 1000)) ms")
    }
}
