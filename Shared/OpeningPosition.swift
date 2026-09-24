import SGFKit

/// The position that thumbnails and previews show: the board after a game's opening moves, as
/// SGF Tools 1.x drew it.
///
/// The number of moves depends on the board: 50 when its shorter side has 19 lines or more,
/// 30 from 13 to 18 lines, and 20 on smaller boards (see ``Look``). Moves are counted as SGF
/// numbers them, passes included, so move 50 is the same move as in other SGF programs. A game
/// shorter than that shows its final position.
struct OpeningPosition: Sendable {
    /// The position.
    let board: Board

    /// The number of moves played to reach it, passes included.
    let movesShown: Int

    /// The number of moves on the game's main line, passes included.
    let totalMoves: Int

    /// The point of the last move shown, or `nil` if there is none or it was a pass.
    let lastMove: SGFPoint?

    /// The opening position of a game.
    init(game: SGFGame) {
        let target = Self.moveCount(for: game.boardSize)
        let moves = game.mainLineMoves
        movesShown = min(target, moves.count)
        totalMoves = moves.count
        board = game.position(afterMainLineMoves: movesShown)
        lastMove = movesShown > 0 ? moves[movesShown - 1].point : nil
    }

    /// The number of opening moves shown on a board of a size.
    static func moveCount(for size: BoardSize) -> Int {
        switch min(size.columns, size.rows) {
        case 19...: Look.openingMovesOnLargeBoards
        case 13 ... 18: Look.openingMovesOnMediumBoards
        default: Look.openingMovesOnSmallBoards
        }
    }

    /// Whether the game goes on past the position shown.
    var isOpening: Bool { movesShown < totalMoves }
}
