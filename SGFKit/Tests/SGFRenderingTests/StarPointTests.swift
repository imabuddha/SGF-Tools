@testable import SGFKit
@testable import SGFRendering
import Testing

@Suite("Star points")
struct StarPointTests {
    /// A literal port of the star point rules in SGF Tools 1.x (`drawGrid` in
    /// `common/SGFDrawBoard.m`), with its 0-based coordinates moved to SGF's 1-based ones.
    private func oldStarPoints(_ size: Int) -> Set<SGFPoint> {
        var points = Set<SGFPoint>()
        func hoshi(_ x: Int, _ y: Int) { points.insert(SGFPoint(column: x + 1, row: y + 1)) }
        if size < 3 || size == 4 { return points }
        if size == 3 {
            hoshi(1, 1)
            return points
        }
        if size == 5 {
            hoshi(1, 1); hoshi(1, 3); hoshi(2, 2); hoshi(3, 1); hoshi(3, 3)
            return points
        }
        let corner = size <= 11 ? 2 : 3
        hoshi(corner, corner)
        hoshi(size - 1 - corner, corner)
        hoshi(corner, size - 1 - corner)
        hoshi(size - 1 - corner, size - 1 - corner)
        if size % 2 == 0 { return points }
        let middle = size / 2
        hoshi(middle, middle)
        if size < 12 { return points }
        hoshi(middle, corner)
        hoshi(middle, size - 1 - corner)
        hoshi(corner, middle)
        hoshi(size - 1 - corner, middle)
        return points
    }

    /// The one deliberate change from 1.x: 13x13 has the usual five star points, the 4-4 points
    /// and the center, where 1.x also had the four side points.
    private func expectedStarPoints(_ size: Int) -> Set<SGFPoint> {
        guard size == 13 else { return oldStarPoints(size) }
        return Set([(4, 4), (4, 10), (7, 7), (10, 4), (10, 10)].map { SGFPoint(column: $0.0, row: $0.1) })
    }

    @Test("Square boards match 1.x, except 13x13", arguments: 1 ... 52)
    func squareBoardsMatchOldVersion(size: Int) throws {
        let boardSize = try #require(BoardSize(size))
        let points = boardSize.starPoints
        #expect(Set(points) == expectedStarPoints(size))
        #expect(points.count == Set(points).count, "no duplicates")
        #expect(points == points.sorted())
    }

    @Test func familiarSizes() throws {
        #expect(try #require(BoardSize(19)).starPoints.map(\.sgf)
            == ["dd", "dj", "dp", "jd", "jj", "jp", "pd", "pj", "pp"])
        // The usual five on 13x13, where 1.x had nine (with the side points too).
        #expect(try #require(BoardSize(13)).starPoints.map(\.sgf) == ["dd", "dj", "gg", "jd", "jj"])
        #expect(Set(try #require(BoardSize(13)).starPoints) != oldStarPoints(13))
        #expect(try #require(BoardSize(15)).starPoints.count == 9)
        #expect(try #require(BoardSize(9)).starPoints.map(\.sgf) == ["cc", "cg", "ee", "gc", "gg"])
        #expect(try #require(BoardSize(5)).starPoints.map(\.sgf) == ["bb", "bd", "cc", "db", "dd"])
        #expect(try #require(BoardSize(3)).starPoints.map(\.sgf) == ["bb"])
        #expect(try #require(BoardSize(4)).starPoints.isEmpty)
        #expect(try #require(BoardSize(2)).starPoints.isEmpty)
    }

    @Test func nineteenByThirteen() throws {
        // Like 13x13, the 13 rows carry no side points; the 19 columns do.
        let size = try #require(BoardSize(columns: 19, rows: 13))
        #expect(size.starPoints.map(\.sgf) == ["dd", "dj", "jd", "jg", "jj", "pd", "pj"])
    }

    @Test func nineteenByNine() throws {
        // Fourth-line columns and third-line rows; side points only on the long edges.
        let size = try #require(BoardSize(columns: 19, rows: 9))
        #expect(size.starPoints.map(\.sgf) == ["dc", "dg", "jc", "je", "jg", "pc", "pg"])
    }

    @Test func thinBoardsHaveNone() throws {
        for (columns, rows) in [(19, 1), (19, 2), (2, 52), (52, 4), (4, 7)] {
            let size = try #require(BoardSize(columns: columns, rows: rows))
            #expect(size.starPoints.isEmpty, "\(size)")
        }
    }

    @Test("Rectangular boards are symmetric", arguments: [3, 5, 6, 9, 12, 13, 19, 21, 52])
    func rectangularBoardsAreSymmetric(columns: Int) throws {
        for rows in 1 ... 52 {
            let size = try #require(BoardSize(columns: columns, rows: rows))
            let transposed = try #require(BoardSize(columns: rows, rows: columns))
            let points = Set(size.starPoints)
            #expect(Set(transposed.starPoints.map { SGFPoint(column: $0.row, row: $0.column) }) == points)
            // Mirror images in both directions, and every point on the board.
            #expect(Set(points.map { SGFPoint(column: columns + 1 - $0.column, row: $0.row) }) == points)
            #expect(Set(points.map { SGFPoint(column: $0.column, row: rows + 1 - $0.row) }) == points)
            #expect(points.allSatisfy { size.contains($0) })
        }
    }
}

@Suite("Coordinates")
struct CoordinateTests {
    @Test func columnLetters() {
        let nineteen = (1 ... 19).map(BoardCoordinates.columnLabel).joined()
        #expect(nineteen == "ABCDEFGHJKLMNOPQRST")
        #expect(BoardCoordinates.columnLabel(25) == "Z")
        #expect(BoardCoordinates.columnLabel(26) == "AA")
        #expect(BoardCoordinates.columnLabel(33) == "AH")
        #expect(BoardCoordinates.columnLabel(34) == "AJ")
        #expect(BoardCoordinates.columnLabel(50) == "AZ")
        #expect(BoardCoordinates.columnLabel(51) == "BA")
        #expect(BoardCoordinates.columnLabel(52) == "BB")
        #expect(BoardCoordinates.columnLabel(0) == "")
    }

    @Test func labelsNeverUseI() {
        let labels = (1 ... 52).map(BoardCoordinates.columnLabel)
        #expect(labels.allSatisfy { !$0.contains("I") })
        #expect(Set(labels).count == 52)
    }

    @Test func rowsCountFromTheBottom() throws {
        #expect(BoardCoordinates.rowLabel(1, rows: 19) == "19")
        #expect(BoardCoordinates.rowLabel(19, rows: 19) == "1")
        #expect(BoardCoordinates.rowLabel(13, rows: 13) == "1")
        let point = try #require(SGFPoint(sgf: "pd"))
        #expect(BoardCoordinates.name(of: point, on: .standard) == "Q16")
        let corner = try #require(SGFPoint(sgf: "ss"))
        #expect(BoardCoordinates.name(of: corner, on: .standard) == "T1")
        let rectangular = try #require(BoardSize(columns: 19, rows: 13))
        #expect(BoardCoordinates.name(of: try #require(SGFPoint(sgf: "aa")), on: rectangular) == "A13")
    }
}
