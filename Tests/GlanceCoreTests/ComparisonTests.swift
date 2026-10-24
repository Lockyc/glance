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

    func testMapSmallGridUsesMaxCellSide() {
        XCTAssertEqual(ComparisonMapLayout.cellSide(columns: 3, rows: 2), 12)
        XCTAssertEqual(ComparisonMapLayout.size(columns: 3, rows: 2), CGSize(width: 50, height: 36))
    }

    func testManyRowsClampToMinimumSide() {
        XCTAssertEqual(ComparisonMapLayout.cellSide(columns: 5, rows: 40), 3)
        XCTAssertEqual(ComparisonMapLayout.size(columns: 5, rows: 40).height, 208)
        XCTAssertEqual(ComparisonMapLayout.cellSide(columns: 5, rows: 15), (120 - 10 - 28) / 15, accuracy: 0.001)
        XCTAssertLessThanOrEqual(ComparisonMapLayout.size(columns: 5, rows: 15).height, 120.001)
    }

    private func window(_ rows: Range<Int>, above: Int, below: Int) -> ComparisonHeaderLayout.Window {
        .init(rows: rows, above: above, below: below)
    }

    func testAllRowsFit() {
        XCTAssertEqual(ComparisonHeaderLayout.visibleRows(current: 2, rows: 6, capacity: 10), window(0..<6, above: 0, below: 0))
        XCTAssertEqual(ComparisonHeaderLayout.visibleRows(current: 2, rows: 6, capacity: 6), window(0..<6, above: 0, below: 0))
    }

    func testWindowCentresOnTheCurrentRow() {
        XCTAssertEqual(ComparisonHeaderLayout.visibleRows(current: 20, rows: 40, capacity: 9), window(17..<24, above: 17, below: 16))
    }

    func testWindowClampsAtTheEnds() {
        XCTAssertEqual(ComparisonHeaderLayout.visibleRows(current: 0, rows: 40, capacity: 9), window(0..<8, above: 0, below: 32))
        XCTAssertEqual(ComparisonHeaderLayout.visibleRows(current: 3, rows: 40, capacity: 9), window(0..<8, above: 0, below: 32))
        XCTAssertEqual(ComparisonHeaderLayout.visibleRows(current: 39, rows: 40, capacity: 9), window(32..<40, above: 32, below: 0))
        XCTAssertEqual(ComparisonHeaderLayout.visibleRows(current: 36, rows: 40, capacity: 9), window(32..<40, above: 32, below: 0))
    }

    func testAMarkerNeverStandsInForASingleRow() {
        XCTAssertEqual(ComparisonHeaderLayout.visibleRows(current: 4, rows: 40, capacity: 9), window(0..<8, above: 0, below: 32))
        XCTAssertEqual(ComparisonHeaderLayout.visibleRows(current: 35, rows: 40, capacity: 9), window(32..<40, above: 32, below: 0))
    }

    func testTinyCapacityShowsOnlyTheCurrentRowWithoutMarkers() {
        let expected = ComparisonHeaderLayout.Window(rows: 5..<6, above: 5, below: 34, showsMarkers: false)
        XCTAssertEqual(ComparisonHeaderLayout.visibleRows(current: 5, rows: 40, capacity: 1), expected)
        XCTAssertEqual(ComparisonHeaderLayout.visibleRows(current: 5, rows: 40, capacity: 0), expected)
        XCTAssertTrue(ComparisonHeaderLayout.visibleRows(current: 20, rows: 40, capacity: 9).showsMarkers)
    }

    func testMapNeverOutgrowsItsBound() {
        let bound = CGSize(width: 400, height: 150)
        XCTAssertLessThanOrEqual(ComparisonMapLayout.size(columns: 5, rows: 40, bound: bound).height, 150)
        XCTAssertLessThanOrEqual(ComparisonMapLayout.size(columns: 5, rows: 200, bound: CGSize(width: 400, height: 800)).height, 800)
        XCTAssertEqual(ComparisonMapLayout.cellSide(columns: 5, rows: 400, bound: bound), 1, "never below a point")
        XCTAssertEqual(ComparisonMapLayout.size(columns: 3, rows: 2, bound: bound), CGSize(width: 50, height: 36), "a roomy bound changes nothing")
        let rect = ComparisonMapLayout.rect(of: cell(39, 4), columns: 5, rows: 40, bound: bound)
        XCTAssertEqual(ComparisonMapLayout.cell(at: CGPoint(x: rect.midX, y: rect.midY), columns: 5, rows: 40, bound: bound), cell(39, 4))
    }

    func testMapCellRectAndHitTestRoundTrip() {
        XCTAssertEqual(ComparisonMapLayout.rect(of: cell(1, 2), columns: 3, rows: 2), CGRect(x: 33, y: 19, width: 12, height: 12))
        for r in 0..<2 {
            for c in 0..<3 {
                let rect = ComparisonMapLayout.rect(of: cell(r, c), columns: 3, rows: 2)
                XCTAssertEqual(ComparisonMapLayout.cell(at: CGPoint(x: rect.midX, y: rect.midY), columns: 3, rows: 2), cell(r, c))
            }
        }
    }

    func testMapHitTestMissesGapsAndOutside() {
        XCTAssertNil(ComparisonMapLayout.cell(at: CGPoint(x: 18, y: 8), columns: 3, rows: 2))
        XCTAssertNil(ComparisonMapLayout.cell(at: CGPoint(x: 2, y: 2), columns: 3, rows: 2))
        XCTAssertNil(ComparisonMapLayout.cell(at: CGPoint(x: 500, y: 8), columns: 3, rows: 2))
    }

    func testComparisonTitle() {
        XCTAssertEqual(ViewerTitle.comparison(variant: "a", row: "chips-open", fileName: "chips-a-open.png",
                                              pixelSize: CGSize(width: 800, height: 600)),
                       "a · chips-open — chips-a-open.png — 800×600")
        XCTAssertEqual(ViewerTitle.comparison(variant: "a", row: "chips-open", fileName: "chips-a-open.png", pixelSize: nil),
                       "a · chips-open — chips-a-open.png")
    }
}
