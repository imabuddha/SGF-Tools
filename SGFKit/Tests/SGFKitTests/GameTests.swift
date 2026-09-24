import Foundation
import Testing
@testable import SGFKit

@Suite("Game: main line and positions")
struct GameTests {
    @Test func mainLineFollowsTheFirstChild() throws {
        let game = try firstGame(Fixtures.game19)
        #expect(game.mainLine.count == 25)
        let moves = game.mainLineMoves.compactMap { $0.point?.sgf }
        #expect(moves.suffix(5) == ["rg", "qg", "dj", "pf", "jd"])
        #expect(game.nodes.count == 26)
    }

    @Test func positionAfterZeroMovesOfAnEvenGameIsEmpty() throws {
        let game = try firstGame(Fixtures.game19)
        #expect(game.position(afterMainLineMoves: 0).compactPosition == "19,,")
    }

    @Test func positionAfterFourMoves() throws {
        let game = try firstGame(Fixtures.game19)
        #expect(game.position(afterMainLineMoves: 4).compactPosition == "19,pdpp,dddp")
    }

    @Test func positionWithACapture() throws {
        let game = try firstGame(Fixtures.game19)
        let before = game.position(afterMainLineMoves: 22)
        #expect(before[pt("qf")] == .white)
        let after = game.position(afterMainLineMoves: 23)
        #expect(after[pt("qf")] == nil)
        #expect(after[pt("pf")] == .black)
        #expect(after.capturedWhiteStones == 1)
        #expect(after.stones(of: .black).count == 12)
        #expect(after.stones(of: .white).count == 10)
    }

    @Test func positionPastTheEndIsTheFinalPosition() throws {
        let game = try firstGame(Fixtures.game19)
        let final = game.position(afterMainLineMoves: 24)
        #expect(game.position(afterMainLineMoves: 1_000) == final)
        #expect(game.position(afterMainLineMoves: .max) == final)
        #expect(final[pt("jd")] == .white)
    }

    @Test func negativeMoveCountIsTreatedAsZero() throws {
        let game = try firstGame(Fixtures.handicap)
        #expect(game.position(afterMainLineMoves: -5) == game.position(afterMainLineMoves: 0))
    }

    @Test func handicapStonesAreInTheStartingPosition() throws {
        let game = try firstGame(Fixtures.handicap)
        #expect(game.position(afterMainLineMoves: 0).compactPosition == "19,dppd,")
        #expect(game.position(afterMainLineMoves: 3).compactPosition == "19,dppdpp,ddqf")
    }

    @Test func variationsDoNotAffectTheMainLinePosition() throws {
        let game = try firstGame(Fixtures.variations)
        let final = game.position(afterMainLineMoves: .max)
        #expect(final.compactPosition == "9,eegg,cc")
        #expect(final[pt("aa")] == nil)
        #expect(final[pt("ab")] == nil)
    }

    @Test func passesCountAsMovesInThePositionIndex() throws {
        let game = try firstGame("(;SZ[9];B[ee];W[];B[cc];W[tt];B[gg])")
        #expect(game.position(afterMainLineMoves: 1).compactPosition == "9,ee,")
        #expect(game.position(afterMainLineMoves: 2).compactPosition == "9,ee,")
        #expect(game.position(afterMainLineMoves: 3).compactPosition == "9,ccee,")
        #expect(game.position(afterMainLineMoves: 5).compactPosition == "9,cceegg,")
    }

    @Test func setupAfterTheRequestedMoveIsNotIncluded() throws {
        let game = try firstGame("(;SZ[9];B[ee];W[cc];AB[aa]C[setup];B[gg])")
        #expect(game.position(afterMainLineMoves: 2)[pt("aa")] == nil)
        #expect(game.position(afterMainLineMoves: 3)[pt("aa")] == .black)
    }

    @Test func setupBeforeTheFirstMoveIsIncludedAtZero() throws {
        let game = try firstGame("(;SZ[9]AB[aa][bb];AE[aa]AW[cc];B[dd])")
        let start = game.position(afterMainLineMoves: 0)
        #expect(start.compactPosition == "9,bb,cc")
    }

    @Test func setupInTheSameNodeAsAMoveComesFirst() throws {
        // FF[4] forbids mixing them, but when a file does, the setup applies before the move.
        let game = try firstGame("(;SZ[9];AE[ee]B[ee])")
        #expect(game.position(afterMainLineMoves: 1)[pt("ee")] == .black)
    }

    @Test func removingStonesWithAE() throws {
        let game = try firstGame("(;SZ[9]AB[aa:cc];B[ee];AE[bb][cc:cc];W[gg])")
        let final = game.position(afterMainLineMoves: .max)
        #expect(final.stones(of: .black).count == 9 - 2 + 1)
        #expect(final[pt("bb")] == nil)
        #expect(final[pt("cc")] == nil)
    }

    @Test func compressedPointListsInSetup() throws {
        let game = try firstGame("(;SZ[9]AB[aa:cc]AW[ee:ff]AE[bb])")
        let start = game.position(afterMainLineMoves: 0)
        #expect(start.stones(of: .black).count == 8)
        #expect(start.stones(of: .white).count == 4)
    }

    @Test func rectangularBoard() throws {
        let game = try firstGame("(;GM[1]FF[4]SZ[19:13];B[sm];W[aa];B[an];W[pd])")
        #expect(game.boardSize == BoardSize(columns: 19, rows: 13))
        let final = game.position(afterMainLineMoves: .max)
        #expect(final.compactPosition == "19:13,sm,aapd")
    }

    @Test func ff3File() throws {
        let game = try firstGame(Fixtures.ff3)
        #expect(game.boardSize == BoardSize(9))
        let final = game.position(afterMainLineMoves: .max)
        #expect(final.stones(of: .black) == [pt("cc"), pt("gg")])
        #expect(final.stones(of: .white) == [pt("ee"), pt("ge")])
    }

    @Test func eachGameOfACollectionHasItsOwnBoard() {
        let games = parse(Fixtures.collection).games
        #expect(games.map { $0.position(afterMainLineMoves: .max).compactPosition }
            == ["9,ee,cc", "13,gg,", "19,pdpp,dd"])
    }

    @Test func mainLineMoveCountCountsEveryMoveIncludingPasses() throws {
        #expect(try firstGame(Fixtures.game19).mainLineMoveCount == 24)
        #expect(try firstGame("(;SZ[9];B[ee];W[];B[tt];AB[aa])").mainLineMoveCount == 3)
    }

    @Test func mainLineMovesIncludePassesAndLeaveOutVariations() throws {
        let game = try firstGame("(;SZ[9]AB[aa];B[ee];W[];AW[bb];B[tt](;W[cc])(;W[gg]))")
        #expect(game.mainLineMoves == [
            Move(color: .black, point: pt("ee")),
            Move(color: .white, point: nil),
            Move(color: .black, point: nil),
            Move(color: .white, point: pt("cc")),
        ])
        #expect(game.mainLineMoves.count == game.mainLineMoveCount)
        #expect(try firstGame("(;SZ[9]AB[aa])").mainLineMoves.isEmpty)
    }

    @Test func legacyCompactPositionAfterTheOpening() throws {
        // 1.x stored the position after the first 50 moves of a 19x19 game this way.
        let game = try firstGame(Fixtures.game19)
        let position = game.position(afterMainLineMoves: 50).compactPosition
        #expect(position.hasPrefix("19,"))
        #expect(position.split(separator: ",", omittingEmptySubsequences: false).count == 3)
        #expect(position == game.position(afterMainLineMoves: 24).compactPosition)
    }
}
