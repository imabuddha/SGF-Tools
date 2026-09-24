import Foundation
import Testing
@testable import SGFKit

@Suite("Board")
struct BoardTests {
    private func board(_ columns: Int = 5, black: [String] = [], white: [String] = []) -> Board {
        var board = Board(size: BoardSize(columns: columns, rows: columns)!)
        for point in black { board.place(.black, at: pt(point)) }
        for point in white { board.place(.white, at: pt(point)) }
        return board
    }

    @Test func startsEmpty() {
        let board = Board(size: .standard)
        #expect(board.stones(of: .black).isEmpty)
        #expect(board.stones(of: .white).isEmpty)
        #expect(board[pt("pd")] == nil)
        #expect(board.compactPosition == "19,,")
    }

    @Test func placeAndRemoveSetupStones() {
        var board = board(black: ["aa", "cc"], white: ["bb"])
        #expect(board[pt("aa")] == .black)
        #expect(board[pt("bb")] == .white)
        board.place(nil, at: pt("aa"))
        #expect(board[pt("aa")] == nil)
        #expect(board.stones(of: .black) == [pt("cc")])
    }

    @Test func setupNeverCaptures() {
        // A white stone placed with no liberties stays: setup is not a move.
        let board = board(black: ["ba", "ab"], white: ["aa"])
        #expect(board[pt("aa")] == .white)
    }

    @Test func pointsOffTheBoardAreIgnored() {
        var board = board()
        board.place(.black, at: pt("zz"))
        let captured = board.play(.white, at: pt("ff"))
        #expect(captured.isEmpty)
        #expect(board.stones(of: .black).isEmpty)
        #expect(board.stones(of: .white).isEmpty)
    }

    @Test func capturesASingleStoneInTheCenter() {
        var board = board(black: ["cc"], white: ["bc", "dc", "cb"])
        let captured = board.play(.white, at: pt("cd"))
        #expect(captured == [pt("cc")])
        #expect(board[pt("cc")] == nil)
        #expect(board.capturedBlackStones == 1)
        #expect(board.capturedWhiteStones == 0)
    }

    @Test func capturesOnTheEdgeAndInTheCorner() {
        var board = board(black: ["aa", "ca"], white: ["ab", "da", "cb"])
        #expect(board.play(.white, at: pt("ba")).sorted() == [pt("aa"), pt("ca")])
        #expect(board.stones(of: .black).isEmpty)
        #expect(board.capturedBlackStones == 2)
    }

    @Test func capturesAGroup() {
        // A black group of three on the left edge, with its last liberty at A2 (ad).
        var board = board(black: ["ab", "ac", "bc"], white: ["aa", "bb", "cc", "bd", "ae"])
        #expect(board.play(.white, at: pt("ad")).sorted() == [pt("ab"), pt("ac"), pt("bc")])
        #expect(board.stones(of: .black).isEmpty)
        #expect(board.capturedBlackStones == 3)
    }

    @Test func capturesTwoGroupsAtOnce() {
        var board = board(black: ["ba", "ab"], white: ["ca", "bb", "ac"])
        #expect(board.play(.white, at: pt("aa")).sorted() == [pt("ab"), pt("ba")])
        #expect(board[pt("aa")] == .white)
    }

    @Test func aMoveThatCapturesIsNotSuicide() {
        // A white stone at aa has no liberty of its own, but it takes the three black stones
        // whose last liberty it fills.
        var board = board(black: ["ba", "ab", "bb"], white: ["ca", "cb", "ac", "bc"])
        let captured = board.play(.white, at: pt("aa"))
        #expect(captured.sorted() == [pt("ab"), pt("ba"), pt("bb")])
        #expect(board[pt("aa")] == .white)
    }

    @Test func singleStoneSuicide() {
        var board = board(white: ["ba", "ab"])
        let captured = board.play(.black, at: pt("aa"))
        #expect(captured == [pt("aa")])
        #expect(board[pt("aa")] == nil)
        #expect(board.capturedBlackStones == 1)
    }

    @Test func multiStoneSuicide() {
        var board = board(black: ["aa"], white: ["ba", "bb", "ac"])
        let captured = board.play(.black, at: pt("ab"))
        #expect(captured.sorted() == [pt("aa"), pt("ab")])
        #expect(board.stones(of: .black).isEmpty)
        #expect(board.stones(of: .white).count == 3)
        #expect(board.capturedBlackStones == 2)
    }

    @Test func playingOnAnOccupiedPointReplacesTheStone() {
        var board = board(black: ["cc"])
        board.play(.white, at: pt("cc"))
        #expect(board[pt("cc")] == .white)
    }

    @Test func snapback() throws {
        let game = try firstGame(Fixtures.snapback)
        let throwIn = game.position(afterMainLineMoves: 1)
        #expect(throwIn[pt("aa")] == .black)
        let taken = game.position(afterMainLineMoves: 2)
        #expect(taken[pt("aa")] == nil)
        #expect(taken[pt("ba")] == .white)
        #expect(taken.capturedBlackStones == 1)
        let retaken = game.position(afterMainLineMoves: 3)
        #expect(retaken.stones(of: .white).isEmpty)
        #expect(retaken.stones(of: .black) == ["aa", "ac", "bc", "ca", "cb"].map { pt($0) })
        #expect(retaken.capturedWhiteStones == 3)
        #expect(retaken.capturedBlackStones == 1)
    }

    @Test func koCaptureAndRecapture() throws {
        let game = try firstGame(Fixtures.ko)
        let start = game.position(afterMainLineMoves: 0)
        #expect(start[pt("cb")] == .black)
        #expect(start[pt("bb")] == nil)
        let whiteTakes = game.position(afterMainLineMoves: 1)
        #expect(whiteTakes[pt("bb")] == .white)
        #expect(whiteTakes[pt("cb")] == nil)
        let blackRetakes = game.position(afterMainLineMoves: 4)
        #expect(blackRetakes[pt("cb")] == .black)
        #expect(blackRetakes[pt("bb")] == nil)
        #expect(blackRetakes.capturedBlackStones == 1)
        #expect(blackRetakes.capturedWhiteStones == 1)
        #expect(blackRetakes.compactPosition == "5,abbabccbee,caccdbed")
    }

    @Test func compactPositionListsPointsColumnByColumn() {
        let board = board(19, black: ["pp", "pd"], white: ["dp", "dd"])
        #expect(board.compactPosition == "19,pdpp,dddp")
    }

    @Test func compactPositionOfARectangularBoard() throws {
        var board = Board(size: try #require(BoardSize(sgf: "19:13")))
        board.place(.black, at: pt("sm"))
        #expect(board.compactPosition == "19:13,sm,")
    }

    @Test func stonesAreListedColumnByColumn() {
        let board = board(black: ["cb", "ab", "ca", "aa"])
        #expect(board.stones(of: .black).map(\.sgf) == ["aa", "ab", "ca", "cb"])
    }

    @Test func largeBoardCapturesUseNoRecursion() throws {
        // A single black chain snaking over most of a 52x52 board, captured in one move.
        let size = try #require(BoardSize(52))
        var board = Board(size: size)
        for column in 1 ... 52 where column.isMultiple(of: 2) == false {
            for row in 1 ... 51 { board.place(.black, at: SGFPoint(column: column, row: row)) }
        }
        for column in 1 ... 52 where column.isMultiple(of: 2) {
            for row in 1 ... 52 { board.place(.white, at: SGFPoint(column: column, row: row)) }
        }
        for column in 1 ... 52 where column.isMultiple(of: 2) == false {
            board.place(.white, at: SGFPoint(column: column, row: 52))
        }
        // Connect the black columns along the top, then fill the last liberty.
        for column in stride(from: 2, through: 50, by: 2) {
            board.place(.black, at: SGFPoint(column: column, row: 1))
        }
        board.place(nil, at: SGFPoint(column: 1, row: 52))
        let captured = board.play(.white, at: SGFPoint(column: 1, row: 52))
        #expect(captured.count == 26 * 51 + 25)
        #expect(board.stones(of: .black).isEmpty)
    }
}
