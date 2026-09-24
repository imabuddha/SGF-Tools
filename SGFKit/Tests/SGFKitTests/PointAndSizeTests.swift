import Foundation
import Testing
@testable import SGFKit

@Suite("Points")
struct PointTests {
    @Test(arguments: [
        ("aa", 1, 1), ("pd", 16, 4), ("zz", 26, 26), ("AA", 27, 27), ("ZZ", 52, 52), ("sA", 19, 27), ("Az", 27, 26),
    ])
    func parsesSGFLetters(sgf: String, column: Int, row: Int) throws {
        let point = try #require(SGFPoint(sgf: sgf))
        #expect(point.column == column)
        #expect(point.row == row)
        #expect(point.sgf == sgf)
    }

    @Test(arguments: ["", "a", "abc", "a1", "1a", "[]", "a "])
    func rejectsOtherText(sgf: String) {
        #expect(SGFPoint(sgf: sgf) == nil)
    }

    @Test func toleratesSurroundingWhitespace() {
        #expect(SGFPoint(sgf: " pd\n") == SGFPoint(column: 16, row: 4))
    }

    @Test func pointsOrderByColumnThenRow() {
        let points = [pt("ba"), pt("ab"), pt("aa"), pt("bb")]
        #expect(points.sorted().map(\.sgf) == ["aa", "ab", "ba", "bb"])
    }

    @Test func compressedPointList() {
        let points = SGFValue(raw: "aa:cc").points
        #expect(Set(points) == Set(["aa", "ab", "ac", "ba", "bb", "bc", "ca", "cb", "cc"].map { pt($0) }))
        #expect(points.count == 9)
    }

    @Test func compressedPointListWithCornersReversed() {
        #expect(Set(SGFValue(raw: "cc:aa").points) == Set(SGFValue(raw: "aa:cc").points))
        #expect(Set(SGFValue(raw: "ca:ac").points) == Set(SGFValue(raw: "aa:cc").points))
    }

    @Test func singlePointAndInvalidValues() {
        #expect(SGFValue(raw: "dd").points == [pt("dd")])
        #expect(SGFValue(raw: "").points.isEmpty)
        #expect(SGFValue(raw: "d").points.isEmpty)
        #expect(SGFValue(raw: "aa:c").points.isEmpty)
    }

    @Test func pointsOfAPropertyExpandEveryValue() throws {
        let game = try firstGame("(;SZ[9]AB[aa:ab][ee][gg:hh])")
        let points = game.root.points("AB")
        #expect(points.count == 2 + 1 + 4)
        #expect(Set(points).count == 7)
        #expect(game.root.points("AW").isEmpty)
    }
}

@Suite("Board sizes")
struct BoardSizeTests {
    @Test(arguments: [("19", 19, 19), ("9", 9, 9), (" 13 ", 13, 13), ("19:13", 19, 13), ("1", 1, 1), ("52", 52, 52), ("52:1", 52, 1)])
    func parsesSZ(sgf: String, columns: Int, rows: Int) throws {
        let size = try #require(BoardSize(sgf: sgf))
        #expect(size.columns == columns)
        #expect(size.rows == rows)
    }

    @Test(arguments: ["", "0", "53", "-9", "nineteen", "19:", ":13", "19:13:5", "19:0", "19x19"])
    func rejectsInvalidSZ(sgf: String) {
        #expect(BoardSize(sgf: sgf) == nil)
    }

    @Test func squareAndRectangular() throws {
        #expect(BoardSize(19)?.isSquare == true)
        #expect(BoardSize(sgf: "13:13")?.isSquare == true)
        #expect(BoardSize(sgf: "19:13")?.isSquare == false)
        #expect(BoardSize(sgf: "19:13")?.sgf == "19:13")
        #expect(BoardSize(sgf: "13:13")?.sgf == "13")
        #expect(BoardSize.standard == BoardSize(19))
    }

    @Test func containsPoints() throws {
        let size = try #require(BoardSize(sgf: "19:13"))
        #expect(size.contains(pt("aa")))
        #expect(size.contains(pt("sm")))
        #expect(!size.contains(pt("sn")))
        #expect(!size.contains(pt("tm")))
    }

    @Test func gameBoardSizeDefaultsTo19() throws {
        let game = try firstGame("(;GM[1];B[aa])")
        #expect(game.boardSize == .standard)
        #expect(game.declaredBoardSize == nil)
    }

    @Test func gameBoardSizeFromSZ() throws {
        #expect(try firstGame("(;SZ[9])").boardSize == BoardSize(9))
        #expect(try firstGame("(;SZ[19:13])").boardSize == BoardSize(columns: 19, rows: 13))
        #expect(try firstGame("(;SZ[19])").declaredBoardSize == .standard)
        #expect(try firstGame("(;SZ[19:13])").declaredBoardSize == BoardSize(columns: 19, rows: 13))
    }

    @Test func invalidSZFallsBackTo19WithAWarning() throws {
        let collection = parse("(;SZ[60];B[aa])")
        #expect(collection.games.first?.boardSize == .standard)
        #expect(collection.games.first?.declaredBoardSize == nil)
        #expect(collection.warnings.map(\.kind) == [.invalidBoardSize("60")])
    }
}

@Suite("Moves")
struct MoveTests {
    @Test func movesAndPasses() throws {
        let game = try firstGame("(;SZ[19];B[pd];W[];B[tt];W[ dd ])")
        let moves = game.mainLine.dropFirst().map { $0.move(on: game.boardSize) }
        #expect(moves == [
            Move(color: .black, point: pt("pd")),
            Move(color: .white, point: nil),
            Move(color: .black, point: nil),
            Move(color: .white, point: pt("dd")),
        ])
        #expect(moves.map { $0?.isPass } == [false, true, true, false])
        #expect(game.root.move(on: game.boardSize) == nil)
    }

    @Test(arguments: [("9", true), ("19", true), ("19:13", true), ("13:19", true), ("20", false), ("21", false), ("25:20", false)])
    func ttIsAPassOnlyOnBoardsUpTo19(size: String, isPass: Bool) throws {
        let boardSize = try #require(BoardSize(sgf: size))
        let game = try firstGame("(;SZ[\(size)];B[tt])")
        let move = try #require(game.mainLine[1].move(on: boardSize))
        #expect(move.isPass == isPass)
        if !isPass, boardSize.contains(pt("tt")) {
            #expect(move.point == pt("tt"))
        }
    }

    @Test func pointsOffTheBoardAreReadAsPasses() throws {
        let game = try firstGame("(;SZ[9];B[jj];W[a1])")
        #expect(game.mainLine[1].move(on: game.boardSize)?.isPass == true)
        #expect(game.mainLine[2].move(on: game.boardSize)?.isPass == true)
    }

    @Test func largestBoard() throws {
        let game = try firstGame("(;SZ[52];B[ZZ];W[tt])")
        #expect(game.mainLine[1].move(on: game.boardSize)?.point == SGFPoint(column: 52, row: 52))
        #expect(game.mainLine[2].move(on: game.boardSize)?.point == SGFPoint(column: 20, row: 20))
    }
}
