import Foundation

/// The games in an SGF file, with any warnings from reading it.
///
/// An SGF file is a collection of one or more game trees, each one game record with its
/// variations. Create one with ``SGFParser/parse(_:options:)`` or ``init(contentsOf:options:)``.
public struct SGFCollection: Sendable {
    /// The games, in file order.
    public let games: [SGFGame]

    /// What the parser tolerated, in file order. Empty for a well-formed file.
    public let warnings: [SGFWarning]

    /// Whether the parser stopped after the first game (see
    /// ``SGFParser/Options/stopAfterFirstGame``) and another game tree follows it.
    let moreGamesFollow: Bool

    /// Creates a collection.
    init(games: [SGFGame], warnings: [SGFWarning] = [], moreGamesFollow: Bool = false) {
        self.games = games
        self.warnings = warnings
        self.moreGamesFollow = moreGamesFollow
    }

    /// Reads and parses an SGF file.
    ///
    /// - Throws: Only if the file can't be read. Parsing itself never fails.
    public init(contentsOf url: URL, options: SGFParser.Options = .init()) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        self = SGFParser.parse(data, options: options)
    }

    /// Whether the file holds more than one game.
    public var isCollection: Bool { games.count > 1 || moreGamesFollow }

    /// The game information of the file, as SGF Tools 1.x indexed it: the fields and move count
    /// of the first game, plus the number of games and the comments of all of them. `nil` if the
    /// file has no games.
    public var info: GameInfo? { GameInfo(collection: self) }
}
