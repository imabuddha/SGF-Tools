import Foundation
import SGFKit
import Testing

/// A game written as a playlist line and read back.
private func roundTrip(_ game: SGFGame, sourceLocation: SourceLocation = #_sourceLocation) throws -> SGFGame {
    let url = URL(fileURLWithPath: "/Volumes/Fixture Disk/Games/a game.sgf")
    let line = try #require(Playlist.line(for: game, url: url), sourceLocation: sourceLocation)
    #expect(!line.contains("\n") && !line.contains("\r"), sourceLocation: sourceLocation)
    #expect(line.count { $0 == "\t" } == 1, sourceLocation: sourceLocation)
    let contents = try Playlist.Contents(data: Data(playlistText([line]).utf8))
    let entry = try #require(contents.entry(at: 0), sourceLocation: sourceLocation)
    #expect(entry.url == url.absoluteString, sourceLocation: sourceLocation)
    return entry.game
}

@Suite("Playlist: format")
struct PlaylistFormatTests {
    @Test func writesAndReadsTheHeaderAndLines() throws {
        let made = try Date("2026-09-25T10:32:00Z", strategy: .iso8601)
        let games = try (0 ..< 3).map { index in
            try game(namedGame(moves: 30 + index))
        }
        let lines = games.enumerated().compactMap { index, game in
            Playlist.line(for: game, url: URL(fileURLWithPath: "/Users/someone/Go/game \(index).sgf"))
        }
        let text = playlistText(lines, found: 64_020, made: made)
        #expect(text.hasPrefix("""
            # SGF Tools screensaver games
            # format: 1
            # made: 2026-09-25T10:32:00Z
            # found: 64020
            # games: 3

            """))
        let contents = try Playlist.Contents(data: Data(text.utf8))
        #expect(contents.header == .init(made: made, found: 64_020, games: 3))
        #expect(contents.count == 3)
        for (index, original) in games.enumerated() {
            let entry = try #require(contents.entry(at: index))
            #expect(entry.url == "file:///Users/someone/Go/game%20\(index).sgf")
            #expect(entry.game.mainLineMoves == original.mainLineMoves)
        }
    }

    @Test func escapesBackslashesAndBracketsAndFlattensTabsAndLineBreaks() throws {
        let sgf = "(;GM[1]PB[Back\\\\slash \\] one]PW[Tab\there\nand there]EV[\\\\]RE[B+R]" + fillerMoves(20) + ")"
        let original = try game(sgf)
        #expect(GameInfo(game: original).blackPlayer == "Back\\slash ] one")
        let line = try #require(Playlist.line(for: original, url: URL(fileURLWithPath: "/tmp/x.sgf")))
        #expect(line.contains("PB[Back\\\\slash \\] one]"))
        #expect(line.contains("EV[\\\\]"))
        let info = GameInfo(game: try roundTrip(original))
        #expect(info.blackPlayer == "Back\\slash ] one")
        #expect(info.whitePlayer == "Tab here and there")
        #expect(info.event == "\\")
    }

    @Test func keepsNonASCIINames() throws {
        let utf8 = try game("(;GM[1]CA[UTF-8]PB[李昌鎬]BR[9段]PW[Émile Müller]EV[名人戦]" + fillerMoves(25) + ")")
        let info = GameInfo(game: try roundTrip(utf8))
        #expect(info.blackPlayer == "李昌鎬")
        #expect(info.blackRank == "9段")
        #expect(info.whitePlayer == "Émile Müller")
        #expect(info.event == "名人戦")

        // A Korean game in EUC-KR comes out in UTF-8.
        let eucKR = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))
        let bytes = try #require("(;GM[1]CA[EUC-KR]PB[이창호]PW[조훈현]\(fillerMoves(25)))".data(using: eucKR))
        let korean = try #require(SGFParser.parse(bytes).games.first)
        let line = try #require(Playlist.line(for: korean, url: URL(fileURLWithPath: "/tmp/k.sgf")))
        #expect(line.contains("CA[UTF-8]PB[이창호]PW[조훈현]"))
        #expect(GameInfo(game: try roundTrip(korean)).whitePlayer == "조훈현")
    }

    @Test func refusesAnotherFormat() {
        let text = "# SGF Tools screensaver games\n# format: 2\n# games: 0\n"
        #expect(throws: Playlist.ReadError.unsupportedFormat("2")) { try Playlist.Contents(data: Data(text.utf8)) }
        let noFormat = "# SGF Tools screensaver games\n# games: 0\n"
        #expect(throws: Playlist.ReadError.unsupportedFormat(nil)) { try Playlist.Contents(data: Data(noFormat.utf8)) }
    }

    @Test func refusesAFileThatIsNotAPlaylist() {
        #expect(throws: Playlist.ReadError.notAPlaylist) { try Playlist.Contents(data: Data("(;GM[1])\n".utf8)) }
        #expect(throws: Playlist.ReadError.notAPlaylist) { try Playlist.Contents(data: Data()) }
        #expect(throws: Playlist.ReadError.notAPlaylist) {
            try Playlist.Contents(data: Data("\n# SGF Tools screensaver games\n# format: 1\n".utf8))
        }
    }

    @Test func skipsALastLineCutShortAndEmptyLines() throws {
        let line = try #require(Playlist.line(for: try game(namedGame()), url: URL(fileURLWithPath: "/tmp/a.sgf")))
        let text = playlistText([line, "", line]) + String(line.prefix(80))
        let contents = try Playlist.Contents(data: Data(text.utf8))
        #expect(contents.count == 2)
        #expect(contents.entry(at: 1) != nil)
    }

    @Test func aLineWithoutATabOrAGameHasNoEntry() throws {
        let text = playlistText(["file:///tmp/a.sgf no tab (;GM[1])", "file:///tmp/b.sgf\tno game here", "\t(;GM[1];B[aa])"])
        let contents = try Playlist.Contents(data: Data(text.utf8))
        #expect(contents.count == 3)
        #expect(contents.entry(at: 0) == nil)
        #expect(contents.entry(at: 1) == nil)
        #expect(contents.entry(at: 2) == nil, "no URL")
    }

    @Test func indexesTenThousandLinesQuickly() throws {
        let line = try #require(Playlist.line(for: try game(namedGame()), url: URL(fileURLWithPath: "/tmp/a.sgf")))
        let data = Data(playlistText(Array(repeating: line, count: 10_000)).utf8)
        #expect(data.count > 4_000_000)
        let clock = ContinuousClock()
        var contents: Playlist.Contents?
        let elapsed = try clock.measure { contents = try Playlist.Contents(data: data) }
        #expect(contents?.count == 10_000)
        #expect(elapsed < .milliseconds(50), "indexed in \(elapsed)")
    }

    @Test func thePlaylistIsInTheRealLibrary() {
        let path = Playlist.defaultURL.path
        #expect(path.hasSuffix("/Library/Application Support/SGF Tools/Screensaver Games.sgfplaylist"))
        #expect(!path.contains("/Containers/"))
    }
}

@Suite("Playlist: lines replay as the files do")
struct PlaylistLineTests {
    /// Synthetic games with everything a line has to carry through.
    static let fixtures: [(name: String, sgf: String)] = [
        ("handicap stones", "(;GM[1]SZ[19]HA[4]PB[Kuro]PW[Shiro]AB[dd][pd][dp][pp]"
            + fillerMoves(70, firstRow: 6, whiteFirst: true) + ")"),
        ("setup in the middle", "(;GM[1]SZ[19]PB[Kuro]PW[Shiro]" + fillerMoves(10, firstRow: 6)
            + ";AE[af][bf]AB[ss]AW[rs]" + fillerMoves(30, firstRow: 10) + ";AB[aa]AE[ss]" + fillerMoves(20, firstRow: 15) + ")"),
        ("passes, tt among them", "(;GM[1]SZ[19]PB[Kuro]PW[Shiro]" + fillerMoves(6, firstRow: 3)
            + ";B[];W[tt];B[tt]" + fillerMoves(60, firstRow: 7, whiteFirst: true, passes: [5, 20]) + ")"),
        ("captures", "(;GM[1]SZ[19]PB[Kuro]PW[Shiro];B[ab];W[aa];B[ba];W[sa];B[rb];W[sb];B[sc];W[ss];B[ra]"
            + fillerMoves(60, firstRow: 5, whiteFirst: true) + ")"),
        ("compressed point lists", "(;GM[1]SZ[19]PB[Kuro]PW[Shiro]AB[aa:cc]AW[qq:ss][ap]"
            + fillerMoves(8, firstRow: 6) + ";AE[bb:bc][rr]" + fillerMoves(50, firstRow: 8) + ")"),
        ("a 19x13 board", "(;GM[1]SZ[19:13]PB[Kuro]PW[Shiro]" + fillerMoves(60, columns: 19) + ")"),
        ("a 9x9 board", "(;GM[1]SZ[9]PB[Kuro]PW[Shiro]" + fillerMoves(60, columns: 9) + ")"),
        ("a 13x13 board", "(;GM[1]SZ[13]PB[Kuro]PW[Shiro]" + fillerMoves(60, columns: 13) + ")"),
        ("a game shorter than 50 moves", "(;GM[1]SZ[19]PB[Kuro]PW[Shiro]" + fillerMoves(23) + ")"),
        ("a collection", "(;GM[1]SZ[19]PB[Kuro]PW[Shiro]" + fillerMoves(55) + ")(;GM[1]SZ[9]PB[B]PW[W];B[ee])"),
        ("variations and comments", "(;GM[1]SZ[19]PB[Kuro]PW[Shiro]C[root]" + fillerMoves(4)
            + ";C[only a comment];N[a name]" + fillerMoves(30, firstRow: 6)
            + "(;B[ss]C[main];W[rs]" + fillerMoves(30, firstRow: 12) + ")(;B[aa]AB[bb]))"),
        ("line breaks in values", "(;GM[1]SZ[19]PB[Kuro]PW[Shiro]"
            + fillerMoves(4) + ";B[p\nd];W[pd\n]" + fillerMoves(40, firstRow: 8) + ")"),
        // Only a value cut off by the end of the file can end in a backslash that escapes nothing.
        ("a trailing backslash at the end of the file", "(;GM[1]SZ[19]PB[Kuro]PW[Shiro]"
            + fillerMoves(25) + ";W[pd\\"),
    ]

    @Test(arguments: fixtures)
    func replaysTheSamePositions(name: String, sgf: String) throws {
        let original = try #require(collection(sgf).games.first)
        let line = try roundTrip(original)
        #expect(line.boardSize == original.boardSize)
        #expect(line.mainLineMoves == Array(original.mainLineMoves.prefix(50)))
        for moves in 0 ... 50 {
            #expect(line.position(afterMainLineMoves: moves) == original.position(afterMainLineMoves: moves),
                    "after \(moves) moves")
        }
        let (a, b) = (GameInfo(game: original), GameInfo(game: line))
        #expect(a.blackPlayer == b.blackPlayer && a.whitePlayer == b.whitePlayer)
        #expect(a.blackRank == b.blackRank && a.whiteRank == b.whiteRank)
        #expect(a.result == b.result && a.event == b.event && a.date == b.date)
    }

    @Test func johnVsGnu() throws {
        let original = try #require(try SGFCollection(contentsOf: Fixtures.johnVsGnu()).games.first)
        let line = try roundTrip(original)
        for moves in 0 ... 50 {
            #expect(line.position(afterMainLineMoves: moves) == original.position(afterMainLineMoves: moves))
        }
        #expect(line.mainLineMoveCount == 50)
        let info = GameInfo(game: line)
        #expect(info.blackPlayer == "John Mifsud" && info.blackRank == "15k")
        #expect(info.whitePlayer == "GNU Go" && info.whiteRank == "NR")
        #expect(info.result == "B+17.5" && info.event == "My So-Called Life" && info.date == "2009-12-10")
        // Only what the screensaver shows: no comments, no other game information.
        #expect(info.gameComment == nil && info.place == nil && info.commentText.isEmpty)
    }

    @Test func linesAreShort() throws {
        let original = try #require(try SGFCollection(contentsOf: Fixtures.johnVsGnu()).games.first)
        let line = try #require(Playlist.line(for: original, url: URL(fileURLWithPath: "/Users/someone/Go/johnVsGnu.sgf")))
        #expect(line.utf8.count < 700)
    }
}

@Suite("Playlist: what counts as a game")
struct ScreensaverGameRuleTests {
    @Test(arguments: [
        ("both players and 60 moves", "PB[B]PW[W]", 60, [], true),
        ("no PB", "PW[W]", 60, [], false),
        ("a PB of spaces", "PB[   ]PW[W]", 60, [], false),
        ("no PW", "PB[B]", 60, [], false),
        ("GM 2", "GM[2]PB[B]PW[W]", 60, [], false),
        ("a GM that isn't a number", "GM[Go]PB[B]PW[W]", 60, [], false),
        ("19 moves", "PB[B]PW[W]", 19, [], false),
        ("20 moves", "PB[B]PW[W]", 20, [], true),
        ("19 moves and a pass", "PB[B]PW[W]", 20, [7], false),
        ("20 moves and a pass", "PB[B]PW[W]", 21, [7], true),
    ] as [(String, String, Int, Set<Int>, Bool)])
    func qualifies(name: String, root: String, moves: Int, passes: Set<Int>, expected: Bool) throws {
        let game = try game("(;SZ[19]\(root)" + fillerMoves(moves, passes: passes) + ")")
        #expect(Playlist.isGame(GameInfo(game: game)) == expected)
        #expect((Playlist.line(for: game, url: URL(fileURLWithPath: "/tmp/a.sgf")) != nil) == expected)
    }
}
