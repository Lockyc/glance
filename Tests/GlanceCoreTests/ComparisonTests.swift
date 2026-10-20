import XCTest
@testable import GlanceCore

final class ComparisonTests: XCTestCase {
    private func u(_ name: String) -> URL { URL(fileURLWithPath: "/x/\(name)") }
    private func cell(_ r: Int, _ c: Int) -> Comparison.Cell { .init(row: r, column: c) }

    private var comparison: Comparison {
        Comparison(variants: [
            Variant(label: "a", files: [u("chips-a-open.png"), u("chips-a.png")]),
            Variant(label: "b", files: [u("chips-b-open.png")]),
            Variant(label: "c", files: [u("c1.png"), u("c2.png")]),
        ])
    }

    func testShape() {
        let c = comparison
        XCTAssertEqual(c.rows, 2)
        XCTAssertEqual(c.columns, 3)
        XCTAssertNil(c.file(at: cell(1, 1)))
        XCTAssertEqual(c.cells, [cell(0, 0), cell(0, 1), cell(0, 2), cell(1, 0), cell(1, 2)])
        XCTAssertEqual(c.files.count, 5)
    }

    func testRowLabels() {
        let c = comparison
        XCTAssertEqual(c.rowLabel(0), "chips-open")
        XCTAssertEqual(c.rowLabel(1), "chips")
        let stacked = Comparison(variants: [Variant(label: "stacked", files: [u("chips2-stacked-current.png")])])
        XCTAssertEqual(stacked.rowLabel(0), "chips2-current")
        let noMatch = Comparison(variants: [Variant(label: "a", files: [u("foo.png")])])
        XCTAssertEqual(noMatch.rowLabel(0), "shot 1")
        let whole = Comparison(variants: [Variant(label: "a", files: [u("a.png")])])
        XCTAssertEqual(whole.rowLabel(0), "shot 1")
        let emptyFirst = Comparison(variants: [
            Variant(label: "a", files: []),
            Variant(label: "b", files: [u("chips-b-open.png")]),
        ])
        XCTAssertEqual(emptyFirst.rowLabel(0), "chips-open")
    }

    func testViewerStep() {
        let c = comparison
        XCTAssertEqual(c.viewerStep(from: cell(0, 2), .right), cell(0, 0))
        XCTAssertEqual(c.viewerStep(from: cell(1, 0), .right), cell(1, 2))
        XCTAssertEqual(c.viewerStep(from: cell(1, 2), .left), cell(1, 0))
        XCTAssertEqual(c.viewerStep(from: cell(0, 0), .down), cell(1, 0))
        XCTAssertNil(c.viewerStep(from: cell(0, 1), .down))
        XCTAssertEqual(c.viewerStep(from: cell(1, 0), .up), cell(0, 0))
        XCTAssertNil(c.viewerStep(from: cell(0, 0), .up))
    }

    func testGridStep() {
        let c = comparison
        XCTAssertEqual(c.gridStep(from: cell(1, 0), .right), cell(1, 1))
        XCTAssertEqual(c.gridStep(from: cell(0, 0), .left), cell(0, 0))
        XCTAssertEqual(c.gridStep(from: cell(1, 2), .down), cell(1, 2))
    }

    func testDuplicateFilesKeepTheirSlots() {
        let c = Comparison(variants: [
            Variant(label: "a", files: [u("same.png")]),
            Variant(label: "b", files: [u("same.png")]),
        ])
        XCTAssertEqual(c.cells.count, 2)
        XCTAssertEqual(c.files, [u("same.png"), u("same.png")])
    }

    func testCellSize() {
        let avail = CGSize(width: 1000, height: 600)
        XCTAssertEqual(ComparisonLayout.cellSize(columns: 2, rows: 2, available: avail, minimumSide: 100, spacing: 10),
                       CGSize(width: 495, height: 295))
        XCTAssertEqual(ComparisonLayout.cellSize(columns: 2, rows: 10, available: avail, minimumSide: 100, spacing: 10).height, 100)
        XCTAssertEqual(ComparisonLayout.cellSize(columns: 20, rows: 2, available: avail, minimumSide: 100, spacing: 10).width, 100)
        XCTAssertEqual(ComparisonLayout.minimumSideRange, HoverPreview.tileSideRange)
    }

    func testComparisonTitle() {
        XCTAssertEqual(ViewerTitle.comparison(variant: "a", row: "chips-open", fileName: "chips-a-open.png",
                                              pixelSize: CGSize(width: 800, height: 600)),
                       "a · chips-open — chips-a-open.png — 800×600")
        XCTAssertEqual(ViewerTitle.comparison(variant: "a", row: "chips-open", fileName: "chips-a-open.png", pixelSize: nil),
                       "a · chips-open — chips-a-open.png")
    }
}
