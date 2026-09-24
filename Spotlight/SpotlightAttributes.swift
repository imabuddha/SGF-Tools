import CoreServices
import Foundation
import SGFKit

/// What Spotlight indexes about an SGF file: the attributes SGF Tools 1.x indexed, with values
/// from SGFKit's ``GameInfo``.
///
/// Standard attributes, such as Participants, Title, and Text content, let any Finder or
/// Spotlight search find games. The custom attributes keep the names 1.x gave them
/// (`com_breedingpinetrees_sgf_*`), so searches saved with 1.x work again; `schema.xml` declares
/// them, and the `schema.strings` files name them for Finder, such as "Black Player".
///
/// The custom attributes, and the standard ones that 1.x took from the first game only, describe
/// the file's first game. The standard attributes that 1.x collected from every game of a
/// collection still do, with each distinct value once: the players and teams (Participants),
/// users (Authors), annotators (Contributors), sources (Publishers), game names (Title), game
/// comments (Description), results (Headline), events (Coverage), and the dates, comments, and
/// node names (Text content).
struct SpotlightAttributes: Equatable {
    /// A value, of one of the types Spotlight stores.
    enum Value: Hashable {
        case string(String)
        case strings([String])
        case integer(Int)
        case real(Double)
        case boolean(Bool)
        case date(Date)

        /// The value as the Foundation object an importer returns: an `NSString`, an `NSArray`
        /// of them, an `NSNumber` (a `CFBoolean` for a Boolean), or an `NSDate`.
        var object: Any {
            switch self {
            case .string(let text): text as NSString
            case .strings(let texts): texts as NSArray
            case .integer(let number): number as NSNumber
            case .real(let number): number as NSNumber
            case .boolean(let flag): flag as NSNumber
            case .date(let date): date as NSDate
            }
        }
    }

    /// The attributes the file has, by name. An attribute with no value is left out.
    let values: [String: Value]

    /// The value of an attribute, or `nil` if the file doesn't give one.
    subscript(name: String) -> Value? { values[name] }

    /// The attributes of a parsed file, or `nil` if it has no games.
    init?(collection: SGFCollection) {
        // Every game's information. The first game's has the fields of GameInfo(collection:);
        // the number of games comes from the collection, and the comments from every game.
        let games = collection.games.map(GameInfo.init(game:))
        guard let first = games.first else { return nil }
        var values: [String: Value] = [:]

        // Standard attributes that 1.x collected from every game.
        values[Standard.title] = Self.joined(games.map(\.gameName), separator: "; ")
        values[Standard.description] = Self.joined(games.map(\.gameComment), separator: "\n\n")
        values[Standard.headline] = Self.joined(games.map(\.result), separator: "; ")
        values[Standard.coverage] = Self.joined(games.map(\.event), separator: "; ")
        values[Standard.authors] = Self.list(games.map(\.user))
        values[Standard.participants] = Self.list(games.flatMap {
            [$0.blackPlayer, $0.whitePlayer, $0.blackTeam, $0.whiteTeam]
        })
        values[Standard.contributors] = Self.list(games.map(\.annotator))
        values[Standard.publishers] = Self.list(games.map(\.source))
        values[Standard.textContent] = Self.joined(games.flatMap {
            [$0.date, $0.commentText.isEmpty ? nil : $0.commentText]
        }, separator: " ")

        // Standard attributes from the first game.
        values[Standard.version] = first.fileFormat.map { .string(String($0)) }
        values[Standard.creator] = first.application.map(Value.string)
        values[Standard.copyright] = first.copyright.map(Value.string)
        values[Standard.namedLocation] = first.place.map(Value.string)
        values[Standard.durationSeconds] = first.timeLimit.map(Value.real)

        // Custom attributes, from the first game.
        values[Name.black] = first.blackPlayer.map(Value.string)
        values[Name.white] = first.whitePlayer.map(Value.string)
        values[Name.blackRank] = first.blackRank.map(Value.string)
        values[Name.whiteRank] = first.whiteRank.map(Value.string)
        values[Name.blackTeam] = first.blackTeam.map(Value.string)
        values[Name.whiteTeam] = first.whiteTeam.map(Value.string)
        values[Name.result] = first.result.map(Value.string)
        values[Name.winner] = first.winner.map(Value.string)
        values[Name.loser] = first.loser.map(Value.string)
        values[Name.event] = first.event.map(Value.string)
        values[Name.round] = first.round.map(Value.string)
        values[Name.datePlayed] = first.datePlayed.flatMap(Self.day(of:)).map(Value.date)
        values[Name.yearPlayed] = first.yearPlayed.map(Value.integer)
        values[Name.ruleset] = first.rules.map(Value.string)
        values[Name.komi] = first.komi.map(Value.real)
        values[Name.handicap] = first.handicap.map(Value.integer)
        values[Name.oldHandicap] = first.oldHandicap.map(Value.string)
        values[Name.overtime] = first.overtime.map(Value.string)
        values[Name.opening] = first.opening.map(Value.string)
        values[Name.gameType] = first.gameTypeName.map(Value.string)
        // SZ's first number (the columns of a rectangular board), or 19 for a game of Go
        // without SZ. A board size SGFKit can't read counts as missing.
        if first.gameType == 1 || collection.games[0].declaredBoardSize != nil {
            values[Name.size] = .integer(first.boardSize.columns)
        }
        values[Name.moves] = .integer(first.moveCount)
        values[Name.numberOfGames] = .integer(games.count)
        values[Name.isCollection] = .boolean(collection.isCollection)

        self.values = values
    }

    /// Each value once, in order, leaving out missing ones.
    private static func distinct(_ values: [String?]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap(\.self).filter { seen.insert($0).inserted }
    }

    /// The distinct values as a list, or `nil` if there are none.
    private static func list(_ values: [String?]) -> Value? {
        let values = distinct(values)
        return values.isEmpty ? nil : .strings(values)
    }

    /// The distinct values joined into one string, or `nil` if there are none.
    private static func joined(_ values: [String?], separator: String) -> Value? {
        let values = distinct(values)
        return values.isEmpty ? nil : .string(values.joined(separator: separator))
    }

    /// A full date as the moment Date Played stores: noon UTC, which is the same day in local
    /// time from UTC-11 to UTC+11, as in 1.x. `nil` for a date without a month or day: a moment
    /// can't say "some day in 1996", and Year Played covers it.
    static func day(of date: PartialDate) -> Date? {
        guard let month = date.month, let day = date.day else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: date.year, month: month, day: day, hour: 12))
    }
}

// MARK: - Reading files

extension SpotlightAttributes {
    /// The most of a file that is read: its first 2 MB.
    ///
    /// Spotlight runs importers in worker processes that macOS expects to stay under 150 MB
    /// (their memory limit; some workers have 100 MB). Indexing takes only about 0.2 seconds a
    /// megabyte there, but the parsed games take 30 times the file's size in memory for a
    /// collection of ordinary games, and up to 70 times for one game that is all moves and
    /// variations.
    /// Of a larger file, only the games in its first 2 MB are indexed, and Games counts only
    /// those. The largest SGF file found so far, 1.78 MB with 4,002 games, is read in full.
    static let byteLimit = 2 << 20

    /// The attributes of an SGF file, or `nil` if it has no games. Only the first `byteLimit`
    /// bytes are read; the parser takes a game cut off there as it would a truncated file.
    ///
    /// - Throws: Only if the file can't be read.
    init?(contentsOf url: URL, byteLimit: Int = SpotlightAttributes.byteLimit) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: byteLimit) ?? Data()
        self.init(collection: SGFParser.parse(data))
    }
}

// MARK: - Attribute names

extension SpotlightAttributes {
    /// The standard Spotlight attributes this sets, as 1.x mapped SGF properties to them.
    enum Standard {
        /// Every game's name (GN).
        static let title = kMDItemTitle as String
        /// Every game's comment about the whole game (GC).
        static let description = kMDItemDescription as String
        /// Every game's result as written (RE).
        static let headline = kMDItemHeadline as String
        /// Every game's event (EV).
        static let coverage = kMDItemCoverage as String
        /// Every game's user who entered it (US).
        static let authors = kMDItemAuthors as String
        /// Every game's players and teams (PB, PW, BT, WT).
        static let participants = kMDItemParticipants as String
        /// Every game's annotator (AN).
        static let contributors = kMDItemContributors as String
        /// Every game's source (SO).
        static let publishers = kMDItemPublishers as String
        /// Every game's dates (DT), comments (C), and node names (N).
        static let textContent = kMDItemTextContent as String
        /// The SGF version (FF).
        static let version = kMDItemVersion as String
        /// The application that wrote the file (AP).
        static let creator = kMDItemCreator as String
        /// The copyright notice (CP).
        static let copyright = kMDItemCopyright as String
        /// Where the game was played (PC).
        static let namedLocation = kMDItemNamedLocation as String
        /// The main time limit in seconds (TM).
        static let durationSeconds = kMDItemDurationSeconds as String

        /// All of them, in the order of `schema.xml`.
        static let all = [
            authors, version, creator, copyright, title, description, headline, coverage,
            namedLocation, participants, contributors, publishers, textContent, durationSeconds,
        ]
    }

    /// The custom attributes, named as in 1.x. Their display names are in the `schema.strings`
    /// files.
    enum Name {
        /// The result as written (RE): "Result".
        static let result = "com_breedingpinetrees_sgf_result"
        /// The event (EV): "Event".
        static let event = "com_breedingpinetrees_sgf_event"
        /// White's name (PW): "White Player".
        static let white = "com_breedingpinetrees_sgf_white"
        /// Black's name (PB): "Black Player".
        static let black = "com_breedingpinetrees_sgf_black"
        /// The number of handicap stones (HA): "Handicap".
        static let handicap = "com_breedingpinetrees_sgf_handicap"
        /// Komi (KM): "Komi".
        static let komi = "com_breedingpinetrees_sgf_komi"
        /// The board size (SZ): "Board Size".
        static let size = "com_breedingpinetrees_sgf_size"
        /// The name of the kind of game (GM), such as "Go": "Game Type".
        static let gameType = "com_breedingpinetrees_sgf_gametype"
        /// Black's rank (BR): "Black Player's Rank".
        static let blackRank = "com_breedingpinetrees_sgf_blackrank"
        /// White's rank (WR): "White Player's Rank".
        static let whiteRank = "com_breedingpinetrees_sgf_whiterank"
        /// Black's team (BT): "Black Team".
        static let blackTeam = "com_breedingpinetrees_sgf_blackteam"
        /// White's team (WT): "White Team".
        static let whiteTeam = "com_breedingpinetrees_sgf_whiteteam"
        /// The opening (ON): "Opening".
        static let opening = "com_breedingpinetrees_sgf_opening"
        /// The overtime method (OT): "Overtime Method".
        static let overtime = "com_breedingpinetrees_sgf_overtime"
        /// The round (RO): "Round Number & Type".
        static let round = "com_breedingpinetrees_sgf_round"
        /// The rules (RU): "Ruleset".
        static let ruleset = "com_breedingpinetrees_sgf_ruleset"
        /// The old-style handicap arrangement (OH): "Old Handicap".
        static let oldHandicap = "com_breedingpinetrees_sgf_oldhandicap"
        /// The first date played (DT), when it is a full date: "Date Played".
        static let datePlayed = "com_breedingpinetrees_sgf_dateplayed"
        /// The year of the first date played (DT): "Year Played".
        static let yearPlayed = "com_breedingpinetrees_sgf_yearplayed"
        /// The winner's name, for a win: "Winner".
        static let winner = "com_breedingpinetrees_sgf_winner"
        /// The loser's name, for a win: "Loser".
        static let loser = "com_breedingpinetrees_sgf_loser"
        /// Whether the file holds more than one game: "Collection".
        static let isCollection = "com_breedingpinetrees_sgf_iscollection"
        /// The number of games in the file: "Games".
        static let numberOfGames = "com_breedingpinetrees_sgf_numgames"
        /// The number of moves on the first game's main line, without passes: "Moves".
        static let moves = "com_breedingpinetrees_sgf_moves"

        /// All of them, in the order of `schema.xml`.
        static let all = [
            result, event, white, black, handicap, komi, size, gameType, blackRank, whiteRank,
            blackTeam, whiteTeam, opening, overtime, round, ruleset, oldHandicap, datePlayed,
            yearPlayed, winner, loser, isCollection, numberOfGames, moves,
        ]
    }
}
