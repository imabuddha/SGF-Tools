import SGFKit
import Testing

@Suite("Opening position")
struct OpeningPositionTests {
    @Test(arguments: [
        (19, 19, 50), (21, 21, 50), (52, 52, 50), (18, 18, 30), (13, 13, 30), (12, 12, 20),
        (9, 9, 20), (5, 5, 20), (19, 13, 30), (13, 19, 30), (19, 9, 20), (25, 19, 50),
    ])
    func moveCount(columns: Int, rows: Int, expected: Int) throws {
        let size = try #require(BoardSize(columns: columns, rows: rows))
        #expect(OpeningPosition.moveCount(for: size) == expected)
    }

    @Test(arguments: [(19, 50), (13, 30), (9, 20)])
    func longGamesStopAfterTheOpening(size: Int, count: Int) throws {
        let game = try game(longGame(size: size, moves: count + 15))
        let position = OpeningPosition(game: game)
        #expect(position.movesShown == count)
        #expect(position.totalMoves == count + 15)
        #expect(position.isOpening)
        #expect(position.board == game.position(afterMainLineMoves: count))
        #expect(position.board.stones(of: .black).count + position.board.stones(of: .white).count == count)
        #expect(position.lastMove == game.mainLineMoves[count - 1].point)
    }

    @Test func passesCount() throws {
        // Moves 10 and 11 are passes, so 50 moves put 48 stones on the board.
        let game = try game(longGame(size: 19, moves: 60, passAt: [10, 11]))
        let position = OpeningPosition(game: game)
        #expect(position.movesShown == 50)
        #expect(position.board.stones(of: .black).count + position.board.stones(of: .white).count == 48)
    }

    @Test func aShortGameShowsItsFinalPosition() throws {
        let game = try game(longGame(size: 19, moves: 12))
        let position = OpeningPosition(game: game)
        #expect(position.movesShown == 12)
        #expect(position.totalMoves == 12)
        #expect(!position.isOpening)
        #expect(position.board == game.position(afterMainLineMoves: .max))
    }

    @Test func aLastPassMarksNothing() throws {
        let game = try game(longGame(size: 9, moves: 20, passAt: [20]))
        #expect(OpeningPosition(game: game).lastMove == nil)
    }

    @Test func setupOnlyGameShowsItsStones() throws {
        let position = OpeningPosition(game: try game("(;SZ[19]AB[dd][pp]AW[dp])"))
        #expect(position.movesShown == 0)
        #expect(position.totalMoves == 0)
        #expect(position.lastMove == nil)
        #expect(position.board.stones(of: .black).count == 2)
        #expect(position.board.stones(of: .white).count == 1)
    }

    @Test func handicapStonesAndVariationsAreHandled() throws {
        // The variation's setup stone must not appear.
        let position = OpeningPosition(game: try game("(;SZ[9]AB[cc][gg];W[ee](;B[ce])(;B[gc]AW[aa]))"))
        #expect(position.movesShown == 2)
        #expect(position.board.stones(of: .black).count == 3)
        #expect(position.board.stones(of: .white).count == 1)
    }
}
