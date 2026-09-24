import SGFKit

extension BoardSize {
    /// The star points (hoshi) drawn on the board, in column-then-row order.
    ///
    /// Square boards follow SGF Tools 1.x, except 13x13:
    /// - none on boards smaller than 3x3, and none on 4x4
    /// - 3x3: the center point
    /// - 5x5: the four points on the second line, and the center
    /// - 6x6 to 11x11: the four corner points on the third line
    /// - 12x12 and larger: the four corner points on the fourth line
    /// - odd sizes from 7x7 up: also the center point
    /// - odd sizes from 15x15 up: also the four side points, midway along the corner points'
    ///   lines.
    ///
    /// 13x13 has the usual five: the 4-4 points and the center. (1.x also put side points on
    /// 13x13, nine in all.)
    ///
    /// A rectangular board applies the same rules to each direction separately, so that it
    /// agrees with the square board of each of its two sizes:
    /// - the corner points sit on the corner lines of each direction (second, third, or fourth
    ///   line, as above); a direction of 3 or 4 lines has none
    /// - the center point needs an odd number of both columns and rows
    /// - the top and bottom side points need an odd number of at least 15 columns, and the left
    ///   and right side points an odd number of at least 15 rows.
    ///
    /// A 19x13 board has seven: corners on the fourth lines, the center, and side points at the
    /// top and bottom only. A 19x9 board has seven too: corners on the fourth columns and third
    /// rows, the center, and side points at the top and bottom only. A board with a dimension
    /// of 1 or 2 has none.
    var starPoints: [SGFPoint] {
        guard columns >= 3, rows >= 3 else { return [] }
        let across = StarLines(lineCount: columns)
        let down = StarLines(lineCount: rows)
        var points: [SGFPoint] = []
        for column in across.corners {
            for row in down.corners {
                points.append(SGFPoint(column: column, row: row))
            }
        }
        if let column = across.middle, let row = down.middle {
            points.append(SGFPoint(column: column, row: row))
        }
        if across.hasSidePoints, let column = across.middle {
            for row in down.corners {
                points.append(SGFPoint(column: column, row: row))
            }
        }
        if down.hasSidePoints, let row = down.middle {
            for column in across.corners {
                points.append(SGFPoint(column: column, row: row))
            }
        }
        return points.sorted()
    }
}

/// The lines that carry star points in one direction of the board, counting from 1.
private struct StarLines {
    /// The two corner lines, or none.
    let corners: [Int]

    /// The middle line, on an odd number of lines.
    let middle: Int?

    /// Whether the middle line carries side points (15 or more lines, odd).
    let hasSidePoints: Bool

    init(lineCount: Int) {
        switch lineCount {
        case 5: corners = [2, 4]
        case 6 ... 11: corners = [3, lineCount - 2]
        case 12...: corners = [4, lineCount - 3]
        default: corners = []
        }
        middle = lineCount % 2 == 1 ? (lineCount + 1) / 2 : nil
        hasSidePoints = lineCount % 2 == 1 && lineCount >= 15
    }
}
