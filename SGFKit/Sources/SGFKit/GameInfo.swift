import Foundation

/// The information about a game that SGF Tools 1.x indexed for Spotlight, plus the values it
/// derived from it.
///
/// Each field comes from the first node on the main line that has the property, which is
/// normally the root. Text fields are SimpleText with surrounding whitespace trimmed, and `nil`
/// when the property is missing or blank.
public struct GameInfo: Sendable, Hashable {
    /// Black's name (PB).
    public var blackPlayer: String?
    /// White's name (PW).
    public var whitePlayer: String?
    /// Black's rank (BR).
    public var blackRank: String?
    /// White's rank (WR).
    public var whiteRank: String?
    /// Black's team (BT).
    public var blackTeam: String?
    /// White's team (WT).
    public var whiteTeam: String?
    /// The result as written (RE), such as `"W+2.5"`. See ``outcome`` for its meaning.
    public var result: String?
    /// The event or tournament (EV).
    public var event: String?
    /// The round (RO).
    public var round: String?
    /// The date or dates played, as written (DT). See ``datePlayed``.
    public var date: String?
    /// Where the game was played (PC).
    public var place: String?
    /// The rules (RU).
    public var rules: String?
    /// Komi (KM).
    public var komi: Double?
    /// The number of handicap stones (HA).
    public var handicap: Int?
    /// The old-style handicap arrangement (OH), a nonstandard property of historical game
    /// records, such as `"B-(W)-B"`: Black in two games out of three, with the parentheses
    /// marking the part of the cycle this game belongs to.
    public var oldHandicap: String?
    /// The main time limit in seconds (TM).
    public var timeLimit: Double?
    /// The overtime method (OT).
    public var overtime: String?
    /// The opening (ON).
    public var opening: String?
    /// The source of the record (SO).
    public var source: String?
    /// The annotator (AN).
    public var annotator: String?
    /// The user who entered the record (US).
    public var user: String?
    /// The application that wrote the file (AP), such as `"CGoban:3"`.
    public var application: String?
    /// The copyright notice (CP).
    public var copyright: String?
    /// The game's name (GN).
    public var gameName: String?
    /// The comment about the whole game (GC), as Text: line breaks are kept.
    public var gameComment: String?
    /// The kind of game (GM): 1 for Go, the default when GM is missing. `nil` if GM isn't a
    /// number.
    public var gameType: Int?
    /// The name of the kind of game, such as `"Go"`, or `nil` if ``gameType`` isn't one FF[4]
    /// lists.
    public var gameTypeName: String?
    /// The SGF version the file declares (FF).
    public var fileFormat: Int?
    /// The board size (SZ); 19x19 if it is missing or invalid.
    public var boardSize: BoardSize

    /// What ``result`` means, or `nil` if there is no result.
    public var outcome: GameResult?
    /// The winner's name, when the result is a win and the winner's name is known.
    public var winner: String?
    /// The loser's name, when the result is a win and the loser's name is known.
    public var loser: String?
    /// The first date in ``date``: a full date, or just a year and month, or a year.
    public var datePlayed: PartialDate?
    /// The year of ``datePlayed``.
    public var yearPlayed: Int?
    /// The number of moves on the main line of the (first) game, not counting passes.
    public var moveCount: Int
    /// The number of games read. After parsing with
    /// ``SGFParser/Options/stopAfterFirstGame`` this is 1 even when more games follow; see
    /// ``isCollection``.
    public var numberOfGames: Int
    /// Whether the file holds more than one game.
    public var isCollection: Bool
    /// All comments (C) and node names (N) of every node, in file order, as SimpleText joined
    /// with spaces, for full-text search. Empty if there are none.
    public var commentText: String

    /// The information about one game.
    public init(game: SGFGame) {
        self.init(game: game, commentSources: [game], numberOfGames: 1, isCollection: false)
    }

    /// The information about a file: the fields and move count of its first game, the number
    /// of games, and the comments of all of them. `nil` if the collection has no games.
    public init?(collection: SGFCollection) {
        guard let first = collection.games.first else { return nil }
        self.init(game: first, commentSources: collection.games, numberOfGames: collection.games.count,
                  isCollection: collection.isCollection)
    }

    private init(game: SGFGame, commentSources: [SGFGame], numberOfGames: Int, isCollection: Bool) {
        let mainLine = game.mainLine
        var values: [String: SGFValue] = [:]
        for node in mainLine {
            for property in node.properties where Self.identifiers.contains(property.identifier) {
                if values[property.identifier] == nil { values[property.identifier] = property.value }
            }
        }
        func simpleText(_ identifier: String) -> String? {
            guard let text = values[identifier]?.simpleText.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty
            else { return nil }
            return text
        }

        blackPlayer = simpleText("PB")
        whitePlayer = simpleText("PW")
        blackRank = simpleText("BR")
        whiteRank = simpleText("WR")
        blackTeam = simpleText("BT")
        whiteTeam = simpleText("WT")
        result = simpleText("RE")
        event = simpleText("EV")
        round = simpleText("RO")
        date = simpleText("DT")
        place = simpleText("PC")
        rules = simpleText("RU")
        komi = values["KM"]?.real
        handicap = values["HA"]?.number
        oldHandicap = simpleText("OH")
        timeLimit = values["TM"]?.real
        overtime = simpleText("OT")
        opening = simpleText("ON")
        source = simpleText("SO")
        annotator = simpleText("AN")
        user = simpleText("US")
        application = simpleText("AP")
        copyright = simpleText("CP")
        gameName = simpleText("GN")
        gameComment = values["GC"].map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        gameType = values["GM"].map(\.number) ?? 1
        gameTypeName = gameType.flatMap(Self.gameTypeName(for:))
        fileFormat = values["FF"]?.number
        boardSize = game.boardSize

        outcome = result.map(GameResult.init(sgf:))
        if case .win(let color, _) = outcome {
            winner = color == .black ? blackPlayer : whitePlayer
            loser = color == .black ? whitePlayer : blackPlayer
        }
        datePlayed = date.flatMap(PartialDate.init(sgfDate:))
        yearPlayed = datePlayed?.year
        moveCount = mainLine.count { $0.move(on: game.boardSize)?.isPass == false }
        self.numberOfGames = numberOfGames
        self.isCollection = isCollection

        var comments: [String] = []
        for sourceGame in commentSources {
            for node in sourceGame.nodes {
                for property in node.properties where property.identifier == "C" || property.identifier == "N" {
                    for value in property.values {
                        let text = value.simpleText.trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty { comments.append(text) }
                    }
                }
            }
        }
        commentText = comments.joined(separator: " ")
    }

    /// The properties the fields come from.
    private static let identifiers: Set<String> = [
        "PB", "PW", "BR", "WR", "BT", "WT", "RE", "EV", "RO", "DT", "PC", "RU", "KM", "HA", "OH", "TM",
        "OT", "ON", "SO", "AN", "US", "AP", "CP", "GN", "GC", "GM", "FF",
    ]

    /// The name of a GM value, as FF[4] lists them (with the spelling of "Hnefatafl" fixed).
    public static func gameTypeName(for gameType: Int) -> String? {
        let names = [
            "Go", "Othello", "Chess", "Gomoku+Renju", "Nine Men's Morris",
            "Backgammon", "Chinese Chess", "Shogi", "Lines of Action", "Ataxx",
            "Hex", "Jungle", "Neutron", "Philosopher's Football", "Quadrature",
            "Trax", "Tantrix", "Amazons", "Octi", "Gess",
            "Twixt", "Zertz", "Plateau", "Yinsh", "Punct",
            "Gobblet", "Hive", "Exxit", "Hnefatafl", "Kuba",
            "Tripples", "Chase", "Tumbling Down", "Sahara", "Byte",
            "Focus", "Dvonn", "Tamsk", "Gipf", "Kropki",
        ]
        return names.indices.contains(gameType - 1) ? names[gameType - 1] : nil
    }
}

/// The meaning of a result (RE).
public enum GameResult: Sendable, Hashable {
    /// A win. The margin is what follows the `+`: points such as `"2.5"`, or `"R"` (resignation),
    /// `"T"` (time), or `"F"` (forfeit), spelled as in the file; empty if none is given.
    case win(StoneColor, margin: String)
    /// A draw: `0`, `Draw`, or `Jigo`.
    case draw
    /// No result, or the game was suspended: `Void`.
    case void
    /// The result is unknown (`?`) or not in FF[4] form.
    case unknown

    /// Interprets an RE value, ignoring case and surrounding whitespace.
    public init(sgf: String) {
        let text = sgf.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("b+") || lowercased.hasPrefix("w+") {
            let margin = text.dropFirst(2).trimmingCharacters(in: .whitespaces)
            self = .win(lowercased.hasPrefix("b") ? .black : .white, margin: margin)
        } else if ["0", "draw", "jigo"].contains(lowercased) {
            self = .draw
        } else if lowercased == "void" {
            self = .void
        } else {
            self = .unknown
        }
    }

    /// The color that won, or `nil` if nobody did.
    public var winner: StoneColor? {
        if case .win(let color, _) = self { return color }
        return nil
    }
}

/// A date that may lack its day, or its month and day, as DT allows: `1996-05-06`, `1996-05`,
/// or `1996`.
public struct PartialDate: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// The year, 1-9999.
    public let year: Int
    /// The month, 1-12, if known.
    public let month: Int?
    /// The day of the month, if known (only when the month is).
    public let day: Int?

    /// Creates a date, or returns `nil` if a component is out of range or there is a day
    /// without a month.
    public init?(year: Int, month: Int? = nil, day: Int? = nil) {
        guard (1 ... 9999).contains(year) else { return nil }
        if let month, !(1 ... 12).contains(month) { return nil }
        if let day {
            guard let month, (1 ... Self.days(inMonth: month, year: year)).contains(day) else { return nil }
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads the first date of a DT value.
    ///
    /// DT is `YYYY-MM-DD`, optionally shortened to `YYYY-MM` or `YYYY`, and may list more dates
    /// after a comma; only the first counts. For older files, `/` and `.` are accepted between
    /// the parts, and text around the date is ignored: the date starts at the first run of
    /// exactly four digits. A month or day out of range is dropped, keeping what came before it.
    public init?(sgfDate: String) {
        guard let date = Self.firstDate(in: sgfDate) else { return nil }
        self = date
    }

    private static func firstDate(in text: String) -> PartialDate? {
        let characters = Array(text)
        var index = 0

        /// Reads the run of ASCII digits at `index`.
        func digitRun() -> (value: Int, length: Int)? {
            var end = index
            while end < characters.count, characters[end].isASCIIDigit { end += 1 }
            guard end > index, end - index <= 9, let value = Int(String(characters[index ..< end])) else {
                return nil
            }
            return (value, end - index)
        }

        /// Reads "-MM" (or with "/" or ".") at `index`: a separator and one or two digits.
        func component() -> Int? {
            guard index < characters.count, ["-", "/", "."].contains(characters[index]) else { return nil }
            index += 1
            guard let run = digitRun(), run.length <= 2 else { return nil }
            index += run.length
            return run.value
        }

        var year: Int?
        while index < characters.count, year == nil {
            guard characters[index].isASCIIDigit else {
                index += 1
                continue
            }
            var end = index
            while end < characters.count, characters[end].isASCIIDigit { end += 1 }
            if end - index == 4 { year = Int(String(characters[index ..< end])) }
            index = end
        }
        guard let year else { return nil }
        guard let month = component(), (1 ... 12).contains(month) else { return PartialDate(year: year) }
        if let day = component(), let date = PartialDate(year: year, month: month, day: day) { return date }
        return PartialDate(year: year, month: month)
    }

    /// The date in DT form: `"1996-05-06"`, `"1996-05"`, or `"1996"`.
    public var description: String {
        var text = String(format: "%04d", year)
        if let month { text += String(format: "-%02d", month) }
        if let day { text += String(format: "-%02d", day) }
        return text
    }

    /// The date as components, with only the known ones set.
    public var dateComponents: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// Orders dates by year, month, and day; a missing month or day sorts first.
    public static func < (lhs: PartialDate, rhs: PartialDate) -> Bool {
        (lhs.year, lhs.month ?? 0, lhs.day ?? 0) < (rhs.year, rhs.month ?? 0, rhs.day ?? 0)
    }

    private static func days(inMonth month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let isLeapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
            return isLeapYear ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}
