import CoreGraphics
import Exhaust
@testable import GlanceCore
import XCTest

/// Properties of the pure layout and navigation functions over every size, not just the examples'.
/// Each input is a struct of raw draws (so Exhaust can reflect and reduce it) with the derived values computed.
final class GeometryPropertyTests: XCTestCase {
    /// A comparison map, and a cell in it picked by fractions of each axis.
    struct Map {
        let columns: Int, rows: Int, width: Double, height: Double, across: Double, down: Double
        var bound: CGSize { CGSize(width: width, height: height) }
        var cell: Comparison.Cell {
            Comparison.Cell(row: min(rows - 1, Int(down * Double(rows))), column: min(columns - 1, Int(across * Double(columns))))
        }
    }

    private let maps = #gen(.int(in: 1...12), .int(in: 1...500), .double(in: 20...1000), .double(in: 20...1000),
                            .double(in: 0...1), .double(in: 0...1)) { columns, rows, width, height, across, down in
        Map(columns: columns, rows: rows, width: width, height: height, across: across, down: down)
    }

    /// The map stays inside the space it may cover (to float rounding: n × side can land 1e-13 pt over);
    /// only once cells are down to a point may it not fit.
    func testMapNeverOutgrowsItsBound() {
        #exhaust(maps) { map in
            let side = ComparisonMapLayout.cellSide(columns: map.columns, rows: map.rows, bound: map.bound)
            let size = ComparisonMapLayout.size(columns: map.columns, rows: map.rows, bound: map.bound)
            return side >= 1 && (side == 1 || (size.width <= map.width + 1e-9 && size.height <= map.height + 1e-9))
        }
    }

    /// Clicking the centre of any cell's square hits that cell.
    func testMapCellCentreHitsItsCell() {
        #exhaust(maps) { map in
            let rect = ComparisonMapLayout.rect(of: map.cell, columns: map.columns, rows: map.rows, bound: map.bound)
            let hit = ComparisonMapLayout.cell(at: CGPoint(x: rect.midX, y: rect.midY), columns: map.columns, rows: map.rows, bound: map.bound)
            return hit == map.cell
        }
    }

    /// Variant lengths (a zero leaves that column's cells empty), a cell picked by fractions, and a move.
    struct Step {
        let lengths: [Int], across: Double, down: Double, move: Int
        var comparison: Comparison {
            Comparison(variants: lengths.enumerated().map { column, length in
                Variant(label: "v\(column)", files: (0..<length).map { URL(fileURLWithPath: "/c/v\(column)-\($0).png") })
            })
        }

        var cell: Comparison.Cell {
            let rows = max(comparison.rows, 1), columns = lengths.count
            return Comparison.Cell(row: min(rows - 1, Int(down * Double(rows))), column: min(columns - 1, Int(across * Double(columns))))
        }

        var direction: Comparison.Move { [.left, .right, .up, .down][move] }
        /// (row, column) per unit of the move.
        var unit: (row: Int, column: Int) { [(0, -1), (0, 1), (-1, 0), (1, 0)][move] }
    }

    private let steps = #gen(.int(in: 0...6).array(length: 1...6), .double(in: 0...1), .double(in: 0...1), .int(in: 0...3)) { lengths, across, down, move in
        Step(lengths: lengths, across: across, down: down, move: move)
    }

    /// The grid's highlight moves one cell that way, or stays only at the grid's edge: never wrapping.
    func testGridStepStaysOnTheGridAndNeverWraps() {
        #exhaust(steps) { step in
            let comparison = step.comparison, cell = step.cell
            let next = comparison.gridStep(from: cell, step.direction)
            guard comparison.rows > 0 else { return next == cell }
            let target = Comparison.Cell(row: cell.row + step.unit.row, column: cell.column + step.unit.column)
            let onGrid = (0..<comparison.rows).contains(target.row) && (0..<comparison.columns).contains(target.column)
            return next == (onGrid ? target : cell)
        }
    }

    /// The viewer lands on the nearest present cell further along the same line, or nowhere: never wrapping.
    func testViewerStepLandsOnTheNearestPresentCellAhead() {
        #exhaust(steps) { step in
            let comparison = step.comparison, cell = step.cell, unit = step.unit
            func ahead(_ n: Int) -> Comparison.Cell { Comparison.Cell(row: cell.row + unit.row * n, column: cell.column + unit.column * n) }
            let reach = max(comparison.rows, comparison.columns)
            let nearest = (1...reach).lazy.map(ahead).first { comparison.file(at: $0) != nil }
            return comparison.viewerStep(from: cell, step.direction) == nearest
        }
    }

    /// A lineup of `count` items, `perRow` to a row, an item picked by fraction, and a move.
    struct LineupStep {
        let count: Int, perRow: Int, at: Double, move: Int
        var index: Int { min(count - 1, Int(at * Double(count))) }
        var direction: Comparison.Move { [.left, .right, .up, .down][move] }
    }

    /// ←/→ move one item and ↑/↓ one row (↓ into a short last row takes its last item); each stays
    /// put only at its end: never wrapping, never sliding along the last row.
    func testLineupStepStaysInRangeAndNeverWraps() {
        let lineups = #gen(.int(in: 1...60), .int(in: 1...12), .double(in: 0...1), .int(in: 0...3)) { count, perRow, at, move in
            LineupStep(count: count, perRow: perRow, at: at, move: move)
        }
        #exhaust(lineups) { lineup in
            let index = lineup.index, perRow = lineup.perRow, count = lineup.count
            let next = LineupLayout.step(from: index, lineup.direction, perRow: perRow, count: count)
            let row = index / perRow, lastRow = (count - 1) / perRow
            return switch lineup.direction {
            case .left: next == max(0, index - 1)
            case .right: next == min(count - 1, index + 1)
            case .up: next == (row == 0 ? index : index - perRow)
            case .down: next == (row == lastRow ? index : min(count - 1, index + perRow))
            }
        }
    }

    struct Layout {
        let columns: Int, rows: Int, width: Double, height: Double, minimumSide: Double
    }

    /// A comparison cell and a lineup cell never drop below the minimum side, whatever the space.
    func testCellsNeverGoBelowTheMinimumSide() {
        let layouts = #gen(.int(in: 1...60), .int(in: 1...60), .double(in: 0...3000), .double(in: 0...3000), .double(in: 60...480)) {
            columns, rows, width, height, minimumSide in
            Layout(columns: columns, rows: rows, width: width, height: height, minimumSide: minimumSide)
        }
        #exhaust(layouts) { layout in
            let available = CGSize(width: layout.width, height: layout.height), minimum = CGFloat(layout.minimumSide)
            let size = ComparisonLayout.cellSize(columns: layout.columns, rows: layout.rows, available: available, minimumSide: minimum, spacing: 8)
            let fit = LineupLayout.fit(count: layout.columns, available: available, minimumSide: minimum, spacing: 8, labelHeight: 20)
            return size.width >= minimum && size.height >= minimum && fit.side >= minimum && (1...layout.columns).contains(fit.perRow)
        }
    }

    /// An image fitted to a view, then zoomed about the view's centre.
    struct Zoom {
        let imageWidth: Double, imageHeight: Double, viewWidth: Double, viewHeight: Double, backing: Double, factor: Double
        var viewport: Viewport {
            Viewport.fit(imageSize: CGSize(width: imageWidth, height: imageHeight), viewSize: CGSize(width: viewWidth, height: viewHeight),
                         backingScale: backing)
                .zoomed(by: factor, about: CGPoint(x: viewWidth / 2, y: viewHeight / 2))
        }
    }

    /// Detail never asks for more pixels than a raster file holds, or than the vector ceiling, at any zoom.
    func testDetailPixelsNeverExceedTheFileOrTheVectorCeiling() {
        let zooms = #gen(.double(in: 1...20000), .double(in: 1...20000), .double(in: 50...3000), .double(in: 50...3000),
                         .double(in: 1...3), .double(in: 0.01...64)) { imageWidth, imageHeight, viewWidth, viewHeight, backing, factor in
            Zoom(imageWidth: imageWidth, imageHeight: imageHeight, viewWidth: viewWidth, viewHeight: viewHeight, backing: backing, factor: factor)
        }
        #exhaust(zooms) { zoom in
            let viewport = zoom.viewport
            let long = Int(max(zoom.imageWidth, zoom.imageHeight).rounded(.up))
            return viewport.detailPixels(isVector: false) <= long && viewport.detailPixels(isVector: true) <= Viewport.vectorPixelCeiling
        }
    }

    struct Window {
        let count: Int, at: Double, radius: Int
        var index: Int { min(count - 1, Int(at * Double(count))) }
    }

    /// The decode window is the current image first, then distinct neighbours, all in range.
    func testDecodeWindowStartsWithCurrentAndHoldsDistinctIndices() {
        let windows = #gen(.int(in: 1...50), .double(in: 0...1), .int(in: 0...6)) { count, at, radius in
            Window(count: count, at: at, radius: radius)
        }
        #exhaust(windows) { window in
            let order = DecodeCache.windowOrder(index: window.index, count: window.count, radius: window.radius)
            return order.first == window.index && Set(order).count == order.count && order.allSatisfy { (0..<window.count).contains($0) }
                && order.count == min(window.count, 2 * max(1, window.radius) + 1)
        }
    }

    /// Tiles dated a number of 9-day gaps apart (so month sections vary), and some of them selected.
    struct Selection {
        let gaps: [Int], picks: [Int]
        var dates: [Date] {
            var day = 0
            return gaps.map { gap in
                day += gap * 9
                return Fixtures.day(day)
            }
        }

        var picked: Set<Int> { Set(picks.map { $0 % gaps.count }) }
    }

    /// With several tiles selected, Return and ←/→ act on the first in grid order, across month sections.
    func testGridActionActsOnTheFirstSelectedTileInGridOrder() {
        let selections = #gen(.int(in: 0...5).array(length: 1...40), .int(in: 0...39).array(length: 1...10)) { gaps, picks in
            Selection(gaps: gaps, picks: picks)
        }
        let calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar
        }()
        #exhaust(selections) { selection in
            let sections = MonthSections(dates: selection.dates, count: selection.gaps.count, calendar: calendar)
            let path = MonthSections.actionPath(Set(selection.picked.map(sections.indexPath(for:))))
            return path.flatMap(sections.index(for:)) == selection.picked.min()
        }
    }
}
