import CoreGraphics
import SGFKit

/// Where everything goes, in pixel space: device pixels, with y pointing up on the output.
///
/// The board and its coordinates are fitted into the rect with square cells and centered. The
/// wood and every grid line start and end on whole pixels, so lines are crisp at any scale. Each
/// line is rounded to the nearest pixel on its own, so neighboring cells can differ by one pixel
/// while the cell size stays the same on average in both directions.
struct BoardLayout {
    /// Below this many device pixels per cell, drawing is simplified (see
    /// ``BoardRenderer/compactCellSize``).
    static let compactCellSize: CGFloat = 6

    /// Below this, stones are drawn as squares that fill their cells and inner lines are left
    /// out.
    static let tinyCellSize: CGFloat = 3

    /// The width of the coordinate band outside the board, on each side that has one, in cells.
    static let labelBand: CGFloat = 0.9

    /// The coordinate font size, as a fraction of the cell.
    static let labelFontRatio: CGFloat = 0.42

    /// Coordinates are left out, and their band with them, if the font would be smaller.
    static let minimumLabelFontSize: CGFloat = 6

    let columns: Int
    let rows: Int

    /// The distance between neighboring lines, before rounding to pixels.
    let cell: CGFloat

    /// The wood, on whole pixels.
    let boardRect: CGRect

    /// The left edge of each vertical line, on a whole pixel, column 1 first.
    let lineLeft: [CGFloat]

    /// The bottom edge of each horizontal line, on a whole pixel, row 1 (the top) first.
    let lineBottom: [CGFloat]

    /// The width of an inner line, in whole pixels.
    let lineWidth: CGFloat

    /// The width of the outer line, in whole pixels. It grows outward from where an inner line
    /// would be, so the edge stones stay centered on the line's inner part.
    let frameWidth: CGFloat

    /// The sides that have coordinates: those asked for, or none if there is no room for them.
    let labelSides: CoordinateSides

    /// The wood beyond the outer lines, in cells: the half cell that edge stones need, plus the
    /// margin.
    let woodBorder: CGFloat

    /// Whether there are coordinates.
    var showsLabels: Bool { !labelSides.isEmpty }

    /// Whether drawing is simplified for a small board.
    var isCompact: Bool { cell < Self.compactCellSize }

    /// Whether the cells are so small that stones become squares.
    var isTiny: Bool { cell < Self.tinyCellSize }

    /// Lays out a board in a rect of pixel space, or returns `nil` if the rect is empty.
    ///
    /// The coordinates go outside the board, in bands of their own, and the board and its
    /// bands together are centered in the rect.
    ///
    /// - Parameters:
    ///   - margin: Extra wood beyond the usual half cell around the grid, in cells.
    ///   - labelSides: The sides to make room for coordinates on.
    init?(size: BoardSize, in rect: CGRect, margin: CGFloat, labelSides: CoordinateSides) {
        guard rect.width.isFinite, rect.height.isFinite, rect.width >= 1, rect.height >= 1 else { return nil }
        let margin = margin.isFinite ? max(0, margin) : 0
        let woodBorder = 0.5 + margin
        let spanX = CGFloat(size.columns - 1)
        let spanY = CGFloat(size.rows - 1)
        func band(_ side: CoordinateSides, of sides: CoordinateSides) -> CGFloat {
            sides.contains(side) ? Self.labelBand : 0
        }
        func cellSize(sides: CoordinateSides) -> CGFloat {
            let width = spanX + 2 * woodBorder + band(.left, of: sides) + band(.right, of: sides)
            let height = spanY + 2 * woodBorder + band(.bottom, of: sides) + band(.top, of: sides)
            return min(rect.width / width, rect.height / height)
        }

        var labelSides = labelSides
        var cell = cellSize(sides: labelSides)
        if !labelSides.isEmpty, cell * Self.labelFontRatio < Self.minimumLabelFontSize {
            labelSides = []
            cell = cellSize(sides: labelSides)
        }
        guard cell.isFinite, cell > 0 else { return nil }

        // The board's center, off the rect's center by half the difference of opposite bands.
        let centerX = rect.midX + (band(.left, of: labelSides) - band(.right, of: labelSides)) * cell / 2
        let centerY = rect.midY + (band(.bottom, of: labelSides) - band(.top, of: labelSides)) * cell / 2
        let width = (spanX + 2 * woodBorder) * cell
        let height = (spanY + 2 * woodBorder) * cell
        let minX = (centerX - width / 2).rounded()
        let minY = (centerY - height / 2).rounded()
        let maxX = max(minX + 1, (centerX + width / 2).rounded())
        let maxY = max(minY + 1, (centerY + height / 2).rounded())
        let boardRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        let lineWidth = max(1, (cell / 30).rounded())
        let frameWidth = cell < 4 ? lineWidth : max(lineWidth + 1, (lineWidth * 1.7).rounded())

        self.columns = size.columns
        self.rows = size.rows
        self.cell = cell
        self.boardRect = boardRect
        self.lineWidth = lineWidth
        self.frameWidth = frameWidth
        self.labelSides = labelSides
        self.woodBorder = woodBorder
        lineLeft = (0 ..< size.columns).map { index in
            (centerX + (CGFloat(index) - spanX / 2) * cell - lineWidth / 2).rounded()
        }
        lineBottom = (0 ..< size.rows).map { index in
            (centerY + (spanY / 2 - CGFloat(index)) * cell - lineWidth / 2).rounded()
        }
    }

    /// The center of a point: the middle of its two lines. Columns and rows count from 1.
    func center(column: Int, row: Int) -> CGPoint {
        CGPoint(x: lineLeft[column - 1] + lineWidth / 2, y: lineBottom[row - 1] + lineWidth / 2)
    }

    /// The center of a point, or `nil` if it is off the board.
    func center(of point: SGFPoint) -> CGPoint? {
        guard (1 ... columns).contains(point.column), (1 ... rows).contains(point.row) else { return nil }
        return center(column: point.column, row: point.row)
    }

    /// The outer line as four rects, which overlap only at the corners. Fill them as one path.
    var frameRects: [CGRect] {
        let grow = frameWidth - lineWidth
        let left = lineLeft[0] - grow
        let right = lineLeft[columns - 1] + frameWidth
        let bottom = lineBottom[rows - 1] - grow
        let top = lineBottom[0] + frameWidth
        return [
            CGRect(x: left, y: lineBottom[0], width: right - left, height: frameWidth),
            CGRect(x: left, y: bottom, width: right - left, height: frameWidth),
            CGRect(x: left, y: bottom, width: frameWidth, height: top - bottom),
            CGRect(x: lineLeft[columns - 1], y: bottom, width: frameWidth, height: top - bottom),
        ]
    }

    /// The inner lines as rects that stop at the outer line, so the inner and outer lines never
    /// overlap. Filled together as one path, the crossings aren't darkened twice either.
    var innerLineRects: [CGRect] {
        guard columns > 2 || rows > 2 else { return [] }
        let insideLeft = lineLeft[0] + lineWidth
        let insideRight = lineLeft[columns - 1]
        let insideBottom = lineBottom[rows - 1] + lineWidth
        let insideTop = lineBottom[0]
        var rects: [CGRect] = []
        if columns > 2, insideTop > insideBottom {
            for x in lineLeft[1 ..< columns - 1] {
                rects.append(CGRect(x: x, y: insideBottom, width: lineWidth, height: insideTop - insideBottom))
            }
        }
        if rows > 2, insideRight > insideLeft {
            for y in lineBottom[1 ..< rows - 1] {
                rects.append(CGRect(x: insideLeft, y: y, width: insideRight - insideLeft, height: lineWidth))
            }
        }
        return rects
    }
}
