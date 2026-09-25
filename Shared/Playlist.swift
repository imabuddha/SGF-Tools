import Foundation
import SGFKit

/// The screensaver's playlist: games that SGF Tools chose from the SGF files Spotlight has
/// indexed, each as its details and its first 50 moves, in one UTF-8 text file that the app
/// writes and the screensaver reads (see `docs/screensaver.md`, 1.6).
///
///     # SGF Tools screensaver games
///     # format: 1
///     # made: 2026-09-25T10:32:00Z
///     # found: 64020
///     # games: 10000
///     file:///Users/someone/Go/example.sgf<tab>(;GM[1]FF[4]CA[UTF-8]SZ[19]PB[…]…;B[pd];W[dp]…)
///
/// Header lines start with `#`. Every other line is a file URL, a tab, and a game in SGF: a root
/// with the game's details, then each main-line node up to the one of the last move kept, with
/// only its moves and setup (B, W, AB, AW, and AE) as written. Replaying a line gives the same
/// positions as replaying the file. SGF rather than a format of its own, so that the screensaver
/// needs no second decoder, and any line can be pasted into an SGF program.
enum Playlist {
    /// The format this code writes and reads. A file of any other format is refused.
    static let format = 1

    /// The first line of every playlist.
    static let title = "# SGF Tools screensaver games"

    /// The moves each game keeps, and the screensaver plays: 50, passes counted, as SGF numbers
    /// moves, on every board size.
    static let moveLimit = 50

    /// The fewest main-line moves, not counting passes, that make a file a game for the
    /// screensaver: the count Spotlight's Moves field holds. Fewer leaves out book diagrams and
    /// problems.
    static let minimumMoves = 20

    /// The largest playlist read: 64 MB, more than six times what 10,000 games take.
    static let sizeLimit = 64 << 20

    /// The name of the playlist's folder, in the real `~/Library/Application Support`.
    static let folderName = "SGF Tools"

    /// The name of the playlist file. Its extension has no declared type, so Spotlight indexes
    /// its name but not its text, and a search for a player doesn't find it.
    static let fileName = "Screensaver Games.sgfplaylist"

    /// The user's real home folder. Inside a sandbox, `NSHomeDirectory()` is the app's container
    /// (or the screensaver host's), so both the app and the screensaver look it up.
    static let realHomeDirectory: URL = {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }()

    /// Where the app writes the playlist and the screensaver reads it.
    static var defaultURL: URL {
        realHomeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    // MARK: - What counts as a game

    /// Whether a game's information makes it a game for the screensaver: it is Go (GM 1, or no
    /// GM), it names both players, and its main line has at least ``minimumMoves`` moves that
    /// aren't passes. The app, the screensaver's direct mode, and the screensaver's check of
    /// each playlist line all use this.
    static func isGame(_ info: GameInfo) -> Bool {
        info.gameType == 1 && info.blackPlayer != nil && info.whitePlayer != nil
            && info.moveCountWithoutPasses >= minimumMoves
    }

    // MARK: - Writing

    /// The facts the header records.
    struct Header: Sendable, Equatable {
        /// When the playlist was made.
        var made: Date
        /// The number of qualifying files Spotlight found.
        var found: Int
        /// The number of games in the playlist.
        var games: Int
    }

    /// The header's lines, each ending in a line break.
    static func text(of header: Header) -> String {
        """
        \(title)
        # format: \(format)
        # made: \(header.made.formatted(.iso8601))
        # found: \(header.found)
        # games: \(header.games)

        """
    }

    /// A game's line, without its line break, or `nil` if the game doesn't qualify
    /// (see ``isGame(_:)``).
    ///
    /// The root gets GM, FF, CA, the board size, and PB, BR, PW, WR, RE, EV, and DT from the
    /// game's information. Every main-line node, from the root up to and including the node of
    /// move ``moveLimit`` (passes count), keeps its B, W, AB, AW, and AE with their values as
    /// written, and nothing else; nodes left empty are dropped.
    static func line(for game: SGFGame, url: URL) -> String? {
        let info = GameInfo(game: game)
        guard isGame(info) else { return nil }
        var sgf = "(;GM[1]FF[4]CA[UTF-8]"
        if let size = game.declaredBoardSize { sgf += "SZ[\(size.sgf)]" }
        let details: [(String, String?)] = [
            ("PB", info.blackPlayer), ("BR", info.blackRank), ("PW", info.whitePlayer), ("WR", info.whiteRank),
            ("RE", info.result), ("EV", info.event), ("DT", info.date),
        ]
        for (identifier, value) in details {
            if let value { sgf += "\(identifier)[\(escaped(value))]" }
        }

        var played = 0
        var isRoot = true
        for node in game.mainLine {
            var properties = ""
            for identifier in ["B", "W", "AB", "AW", "AE"] {
                guard let property = node[identifier] else { continue }
                properties += identifier + property.values.map { "[\(cleaned($0.raw))]" }.joined()
            }
            if isRoot {
                sgf += properties
                isRoot = false
            } else if !properties.isEmpty {
                sgf += ";" + properties
            }
            if node.move(on: game.boardSize) != nil {
                played += 1
                if played == moveLimit { break }
            }
        }
        return url.absoluteString + "\t" + sgf + ")"
    }

    /// Text as an SGF value: `\` and `]` escaped, and tabs and line breaks turned into spaces.
    static func escaped(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\\" || scalar == "]" {
                result.append("\\")
                result.append(scalar)
            } else {
                result.append(isBreak(scalar) ? " " : scalar)
            }
        }
        return String(result)
    }

    /// A raw value, escapes and all, made fit for one line: a tab or line break becomes a space,
    /// and a backslash left unpaired at the end, which would escape the closing `]`, gets its
    /// pair. Neither changes what the value means as a point, a compressed list, or a pass: a
    /// point ignores the whitespace around it, and whitespace or a backslash inside a value
    /// already kept it from being a point.
    private static func cleaned(_ raw: String) -> String {
        var result = String.UnicodeScalarView()
        var trailingBackslashes = 0
        for scalar in raw.unicodeScalars {
            result.append(isBreak(scalar) ? " " : scalar)
            trailingBackslashes = scalar == "\\" ? trailingBackslashes + 1 : 0
        }
        if trailingBackslashes % 2 == 1 { result.append("\\") }
        return String(result)
    }

    /// Whether a scalar is a tab or a line break, which a line can't hold.
    private static func isBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "\t", "\n", "\r", "\u{0B}", "\u{0C}": true
        default: false
        }
    }

    // MARK: - Reading

    /// Why a file isn't a playlist this code can read.
    enum ReadError: Error, Equatable {
        /// The file doesn't start with ``Playlist/title``.
        case notAPlaylist
        /// The header names another format, or none.
        case unsupportedFormat(String?)
    }

    /// One game line: the file it came from, and its game.
    struct Entry: Sendable {
        /// The file's URL, as written (`URL.absoluteString`). The screensaver never opens it.
        let url: String
        /// The line's game.
        let game: SGFGame
    }

    /// A playlist's header and the byte ranges of its game lines, which are parsed only when a
    /// game is picked.
    struct Contents: Sendable {
        /// The header's facts. A value the header lacks is 0, or the distant past for the date.
        let header: Header

        /// The file's bytes.
        let data: Data

        /// Each game line's bytes, without the line break, as offsets from the start of ``data``.
        let lines: [Range<Int>]

        /// Indexes a playlist's bytes. The first line must be ``Playlist/title``. Lines end in a
        /// line break (`\n`); a last line without one was cut short and is skipped, as are empty
        /// lines.
        init(data: Data) throws(ReadError) {
            var headerValues: [String: String] = [:]
            var lines: [Range<Int>] = []
            var sawTitle = false
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var start = 0
                while start < raw.count,
                      let found = memchr(base + start, 0x0A, raw.count - start) {
                    let end = base.distance(to: UnsafeRawPointer(found))
                    defer { start = end + 1 }
                    if start == 0 {
                        let first = String(decoding: UnsafeRawBufferPointer(rebasing: raw[0 ..< end]), as: UTF8.self)
                        sawTitle = first == Playlist.title
                        if !sawTitle { return }
                        continue
                    }
                    guard end > start else { continue }
                    if raw[start] == UInt8(ascii: "#") {
                        let text = String(decoding: UnsafeRawBufferPointer(rebasing: raw[start ..< end]), as: UTF8.self)
                        if let colon = text.firstIndex(of: ":") {
                            let key = text[text.index(after: text.startIndex) ..< colon].trimmingCharacters(in: .whitespaces)
                            let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                            headerValues[key] = value
                        }
                    } else {
                        lines.append(start ..< end)
                    }
                }
            }
            guard sawTitle else { throw .notAPlaylist }
            guard headerValues["format"] == String(Playlist.format) else {
                throw .unsupportedFormat(headerValues["format"])
            }
            header = Header(
                made: headerValues["made"].flatMap { try? Date($0, strategy: .iso8601) } ?? .distantPast,
                found: headerValues["found"].flatMap { Int($0) } ?? 0,
                games: headerValues["games"].flatMap { Int($0) } ?? 0
            )
            self.data = data
            self.lines = lines
        }

        /// The number of game lines.
        var count: Int { lines.count }

        /// The game line at an index, parsed, or `nil` if it has no tab or no game.
        func entry(at index: Int) -> Entry? {
            guard let (url, sgf) = parts(at: index), !url.isEmpty,
                  let game = SGFParser.parse(Data(sgf), options: .init(stopAfterFirstGame: true)).games.first
            else { return nil }
            return Entry(url: url, game: game)
        }

        /// The URL of the game line at an index, without parsing its game, or `nil` if it has no
        /// tab.
        func url(at index: Int) -> String? {
            parts(at: index)?.url
        }

        private func parts(at index: Int) -> (url: String, sgf: Data.SubSequence)? {
            let range = lines[index]
            let bytes = data[data.startIndex + range.lowerBound ..< data.startIndex + range.upperBound]
            guard let tab = bytes.firstIndex(of: 0x09) else { return nil }
            return (String(decoding: bytes[..<tab], as: UTF8.self), bytes[bytes.index(after: tab)...])
        }
    }
}
