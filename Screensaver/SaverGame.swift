import Foundation
import SGFKit

/// A game ready to play on a screen: its positions from the start to the last move played, the
/// point of each move, its details, and where it came from.
struct SaverGame: Sendable {
    /// Where a game came from (see `docs/screensaver.md`, 1.8).
    enum Source: String, Sendable, CustomStringConvertible {
        /// A line of the playlist the app wrote.
        case playlist
        /// A file read in direct mode.
        case direct
        /// The game the screensaver carries.
        case own = "own game"

        /// The source for the log, as in "picked a game from the playlist".
        var description: String {
            switch self {
            case .playlist: "the playlist"
            case .direct: "direct mode"
            case .own: "the screensaver's own game"
            }
        }
    }

    /// The line added to the details of the screensaver's own game.
    static let ownGameHint = "Open SGF Tools to choose games for this screensaver."

    let source: Source

    /// What tells games apart, so that screens don't show the same one: the file's URL, as the
    /// playlist writes it.
    let identity: String

    let boardSize: BoardSize

    /// The position after each number of moves, from 0 (the setup and handicap stones) to
    /// ``moveCount``.
    let positions: [Board]

    /// The point of each move, from move 1 at index 1; `nil` for a pass. Index 0 is `nil`.
    let lastMoves: [SGFPoint?]

    let details: SaverDetails

    /// The number of moves played: ``Playlist/moveLimit``, or the whole main line if it is
    /// shorter, passes counted.
    var moveCount: Int { positions.count - 1 }

    /// A game from a parsed file or playlist line, or `nil` if it doesn't qualify (see
    /// ``Playlist/isGame(_:)``) and `mustQualify` is set.
    init?(game: SGFGame, source: Source, identity: String, hint: String? = nil, mustQualify: Bool = true,
          locale: Locale = .current) {
        let info = GameInfo(game: game)
        guard !mustQualify || Playlist.isGame(info) else { return nil }
        let moves = game.mainLineMoves.prefix(Playlist.moveLimit)
        self.source = source
        self.identity = identity
        boardSize = game.boardSize
        positions = (0 ... moves.count).map { game.position(afterMainLineMoves: $0) }
        lastMoves = [nil] + moves.map(\.point)
        details = SaverDetails(info: info, hint: hint, locale: locale)
    }

    /// The screensaver's own game, John Mifsud's 2009 game against GNU Go, from the
    /// screensaver's bundle (not `Bundle.main`, which is the host's), with a hint to open SGF
    /// Tools. It plays when there are no other games.
    static func own(in bundle: Bundle) -> SaverGame? {
        guard let url = bundle.url(forResource: "johnVsGnu", withExtension: "sgf"),
              case .success(let data) = GameFileReader.readPrefix(ofFileAt: url.path, limit: GameFileReader.byteLimit),
              let game = SGFParser.parse(data, options: .init(stopAfterFirstGame: true)).games.first
        else { return nil }
        return SaverGame(game: game, source: .own, identity: "own:johnVsGnu", hint: ownGameHint, mustQualify: false)
    }
}
