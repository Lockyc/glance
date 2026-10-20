import CoreGraphics
import Foundation

/// Variants as columns, shots as rows: row `r` holds the r-th file of every variant.
public struct Comparison: Equatable {
    public struct Cell: Hashable {
        public let row: Int
        public let column: Int

        public init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }
    }

    public enum Move { case left, right, up, down }

    public let variants: [Variant]

    /// Present cells, row-major. The window's `FolderModel` lists `files` in this order, so index i ↔ `cells[i]`.
    public let cells: [Cell]

    public init(variants: [Variant]) {
        self.variants = variants
        let rows = variants.map(\.files.count).max() ?? 0
        cells = (0..<rows).flatMap { row in
            variants.indices.filter { row < variants[$0].files.count }.map { Cell(row: row, column: $0) }
        }
    }

    /// The longest variant.
    public var rows: Int { variants.map(\.files.count).max() ?? 0 }
    public var columns: Int { variants.count }

    /// nil = empty cell.
    public func file(at cell: Cell) -> URL? {
        guard variants.indices.contains(cell.column), cell.row >= 0,
              cell.row < variants[cell.column].files.count else { return nil }
        return variants[cell.column].files[cell.row]
    }

    public var files: [URL] { cells.compactMap(file(at:)) }

    /// The shot's name with the variant label removed from the first present file's stem
    /// (`chips-a-open.png` under `a` → `chips-open`); `shot N` when nothing is left to name it.
    public func rowLabel(_ row: Int) -> String {
        let fallback = "shot \(row + 1)"
        guard let cell = cells.first(where: { $0.row == row }), let url = file(at: cell) else { return fallback }
        let label = variants[cell.column].label
        var tokens = Self.tokens(url.deletingPathExtension().lastPathComponent)
        guard let index = tokens.firstIndex(of: label) else { return fallback }
        if index > 0 {
            tokens.removeSubrange((index - 1)...index)
        } else {
            tokens.removeSubrange(index...min(index + 1, tokens.count - 1))
        }
        let result = tokens.joined()
        return result.isEmpty ? fallback : result
    }

    /// Splits on `-`, `_` and space, keeping each delimiter as its own token.
    private static func tokens(_ stem: String) -> [String] {
        var out: [String] = []
        var word = ""
        for ch in stem {
            if ch == "-" || ch == "_" || ch == " " {
                if !word.isEmpty { out.append(word); word = "" }
                out.append(String(ch))
            } else {
                word.append(ch)
            }
        }
        if !word.isEmpty { out.append(word) }
        return out
    }

    /// Clamps at the grid's edges; may land on an empty cell.
    public func gridStep(from cell: Cell, _ move: Move) -> Cell {
        guard rows > 0, columns > 0 else { return cell }
        switch move {
        case .left: return Cell(row: cell.row, column: max(0, cell.column - 1))
        case .right: return Cell(row: cell.row, column: min(columns - 1, cell.column + 1))
        case .up: return Cell(row: max(0, cell.row - 1), column: cell.column)
        case .down: return Cell(row: min(rows - 1, cell.row + 1), column: cell.column)
        }
    }

    /// Skips empty cells. ←/→ wrap within the row; ↑/↓ are nil when no present cell lies that way in the column.
    public func viewerStep(from cell: Cell, _ move: Move) -> Cell? {
        switch move {
        case .left, .right:
            let step = move == .right ? 1 : -1
            for offset in 1..<max(columns, 2) {
                let column = ((cell.column + step * offset) % columns + columns) % columns
                let candidate = Cell(row: cell.row, column: column)
                if file(at: candidate) != nil { return candidate }
            }
            return nil
        case .up, .down:
            let step = move == .down ? 1 : -1
            var row = cell.row + step
            while row >= 0 && row < rows {
                let candidate = Cell(row: row, column: cell.column)
                if file(at: candidate) != nil { return candidate }
                row += step
            }
            return nil
        }
    }
}

public enum ComparisonLayout {
    public static let minimumSideRange: ClosedRange<CGFloat> = HoverPreview.tileSideRange
    public static let defaultMinimumSide: CGFloat = 160

    /// Each axis divides the available space evenly but never drops below `minimumSide`;
    /// the window scrolls when the grid outgrows it.
    public static func cellSize(columns: Int, rows: Int, available: CGSize, minimumSide: CGFloat, spacing: CGFloat) -> CGSize {
        func side(_ count: Int, _ space: CGFloat) -> CGFloat {
            let n = CGFloat(max(count, 1))
            return max(minimumSide, (space - spacing * (n - 1)) / n)
        }
        return CGSize(width: side(columns, available.width), height: side(rows, available.height))
    }
}
