import Foundation
import SGFKit

/// The game information a preview shows, as text: only the fields the file has.
struct GameSummary: Sendable, Equatable {
    /// One player: their name, with rank and team if the file gives them.
    struct Player: Sendable, Equatable {
        /// The name and rank, such as "Black Tester 3d", or the rank alone if the name is
        /// missing.
        let name: String
        /// The player's team, if any.
        let team: String?
    }

    /// One labeled line of information, such as "Komi" and "6.5".
    struct Field: Sendable, Equatable {
        let label: String
        let value: String
    }

    /// The game's name (GN).
    let title: String?

    /// Black and White, if the file names them or gives their ranks or teams.
    let black: Player?
    let white: Player?

    /// The result, in words, such as "White won by resignation".
    let result: String?

    /// The event, round, date, place, rules, komi, handicap, moves, and games, in that order,
    /// each only if the file has it.
    let fields: [Field]

    /// The comment about the whole game (GC), with its line breaks.
    let gameComment: String?

    /// The summary of a file, or `nil` if it has no games.
    ///
    /// - Parameter locale: The locale for dates and numbers.
    init?(collection: SGFCollection, locale: Locale = .current) {
        guard let info = collection.info, let game = collection.games.first else { return nil }
        self.init(info: info, moveCount: game.mainLineMoveCount, locale: locale)
    }

    /// The summary of a file's game information.
    ///
    /// - Parameter moveCount: The number of moves of the first game's main line, passes
    ///   included, so that it matches the move numbers. (``GameInfo/moveCount`` leaves passes
    ///   out, as 1.x did.)
    init(info: GameInfo, moveCount: Int, locale: Locale = .current) {
        title = info.gameName
        black = Self.player(name: info.blackPlayer, rank: info.blackRank, team: info.blackTeam)
        white = Self.player(name: info.whitePlayer, rank: info.whiteRank, team: info.whiteTeam)
        result = info.outcome.map { Self.describe($0, as: info.result ?? "", locale: locale) }

        var fields: [Field] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { fields.append(Field(label: label, value: value)) }
        }
        add("Event", info.event)
        add("Round", info.round)
        add("Date", info.date.map { Self.describeDate($0, locale: locale) })
        add("Place", info.place)
        add("Rules", info.rules)
        add("Komi", info.komi.map { Self.number($0, locale: locale) })
        // FF[4] allows only 2 or more; 0 and 1 mean an even game.
        add("Handicap", info.handicap.flatMap { $0 >= 2 ? "\($0) stones" : nil })
        add("Moves", moveCount > 0 ? Self.integer(moveCount, locale: locale) : nil)
        if info.isCollection {
            add("Games", info.numberOfGames > 1 ? Self.integer(info.numberOfGames, locale: locale) : "Several")
        }
        self.fields = fields
        gameComment = info.gameComment
    }

    // MARK: - Wording

    /// A player's line, or `nil` if the file says nothing about them.
    private static func player(name: String?, rank: String?, team: String?) -> Player? {
        let line = [name, rank].compactMap(\.self).joined(separator: " ")
        guard !line.isEmpty || team != nil else { return nil }
        return Player(name: line.isEmpty ? "Unknown" : line, team: team)
    }

    /// A result in words: "Black won by 17.5 points", "White won by resignation", "Draw", and
    /// so on. A result that isn't in FF[4] form is shown as written.
    static func describe(_ outcome: GameResult, as written: String, locale: Locale = .current) -> String {
        switch outcome {
        case .win(let color, let margin):
            let winner = color == .black ? "Black" : "White"
            return "\(winner) won" + describeMargin(margin, locale: locale)
        case .draw:
            return "Draw"
        case .void:
            return "No result"
        case .unknown:
            let text = written.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty || text == "?" ? "Unknown result" : text
        }
    }

    /// The end of a win's description, from what follows the `+`: " by 2.5 points",
    /// " by resignation", " on time", " by forfeit", or nothing.
    private static func describeMargin(_ margin: String, locale: Locale) -> String {
        let text = margin.trimmingCharacters(in: .whitespaces)
        switch text.lowercased() {
        case "":
            return ""
        case "r", "resign", "resignation":
            return " by resignation"
        case "t", "time":
            return " on time"
        case "f", "forfeit":
            return " by forfeit"
        default:
            // Points are an SGF Real, as komi is: "2.5", or "2,5" with a decimal comma.
            guard let points = SGFValue(raw: text).real, points >= 0 else { return " (\(text))" }
            if points == 0.5 { return " by half a point" }
            return " by \(number(points, locale: locale)) point\(points == 1 ? "" : "s")"
        }
    }

    /// A date from DT, spelled out when it is one full or partial date ("March 17, 2024",
    /// "March 2024", "2024"), and as written otherwise, such as for a list of days.
    static func describeDate(_ written: String, locale: Locale = .current) -> String {
        guard let date = PartialDate(sgfDate: written), date.description == written else { return written }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let day = calendar.date(from: DateComponents(year: date.year, month: date.month ?? 1, day: date.day ?? 1))
        else { return written }
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
        if date.day != nil {
            style = style.year().month(.wide).day()
        } else if date.month != nil {
            style = style.year().month(.wide)
        } else {
            style = style.year()
        }
        return day.formatted(style)
    }

    private static func number(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 2)).locale(locale))
    }

    private static func integer(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }
}
