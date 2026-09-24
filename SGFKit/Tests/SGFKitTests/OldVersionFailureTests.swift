import Foundation
import Testing
@testable import SGFKit

/// One test (or a small group) for each failure of SGF Tools 1.x listed in section 6 of
/// docs/old-version-analysis.md. The fixtures are synthetic stand-ins for the files that broke it.
///
/// The last lesson there, the installer that ran `find /` over the whole disk, is not about
/// parsing, so it has no test here.
@Suite("1.x failures")
struct OldVersionFailureTests {
    // MARK: Anything before the first "(" killed the parse.

    @Test func htmlEscapedByteOrderMarkBeforeTheGame() throws {
        // The "why bad" files start with the literal text "&#65279;", left by a web download.
        let text = "&#65279;(;GM[1]FF[4]CA[UTF-8]AP[CGoban:3]ST[2]\r\n\r\nRU[Japanese]SZ[19]KM[6.50]\r\n"
            + "PW[White]PB[Black]RE[B+R]\r\n;B[pd];W[dp];B[pp];W[dd])\r\n"
        let collection = parse(text)
        let game = try #require(collection.games.first)
        #expect(game.mainLineMoveCount == 4)
        #expect(GameInfo(game: game).winner == "Black")
        #expect(collection.warnings.map(\.kind) == [.skippedText(byteCount: 8)])
    }

    @Test func byteOrderMarkBeforeTheGame() throws {
        let collection = parse(bytes: [0xEF, 0xBB, 0xBF] + ascii("(;GM[1]SZ[19];B[pd])"))
        #expect(collection.games.first?.mainLineMoveCount == 1)
        #expect(collection.warnings.isEmpty)
    }

    // MARK: Encodings: only CA[UTF-8] was recognized, and everything else was read as Latin-1.

    @Test func utf8DeclaredButReallyLatin1() throws {
        // Like four of the "why bad" files: CA[UTF-8], but the names are in Latin-1.
        let bytes = ascii("(;GM[1]FF[4]CA[UTF-8]SZ[19]PW[Andr") + [0xE9] + ascii("]PB[J") + [0xF6]
            + ascii("rg]C[Gr") + [0xFC, 0xDF] + ascii("e];B[pd])")
        let collection = parse(bytes: bytes)
        let info = try #require(collection.info)
        #expect(info.whitePlayer == "Andr\u{E9}")
        #expect(info.blackPlayer == "J\u{F6}rg")
        #expect(info.commentText == "Gr\u{FC}\u{DF}e")
        #expect(collection.warnings.map(\.kind) == [.encodingFallback(declared: "UTF-8", used: "Windows-1252")])
    }

    @Test func lowercaseUTF8Charset() throws {
        // 1.x compared the CA value case-sensitively, so CA[utf-8] was read as Latin-1.
        let info = try #require(parse(bytes: ascii("(;CA[utf-8]PB[Jos") + [0xC3, 0xA9] + ascii("])")).info)
        #expect(info.blackPlayer == "Jos\u{E9}")
    }

    @Test func otherCharsetsAreHonored() throws {
        // "Łódź" in ISO-8859-2 is A3 F3 64 BC.
        let bytes = ascii("(;CA[ISO-8859-2]PC[") + [0xA3, 0xF3, 0x64, 0xBC] + ascii("])")
        #expect(try #require(parse(bytes: bytes).info).place == "\u{141}\u{F3}d\u{17A}")
    }

    // MARK: Escapes: "\]" and soft line breaks were never unescaped.

    @Test func escapesAreRemoved() throws {
        let info = try #require(parse(#"(;GN[Game \[1\]]C[He said \]\\ twice])"#).info)
        #expect(info.gameName == "Game [1]")
        #expect(info.commentText == #"He said ]\ twice"#)
    }

    @Test func softLineBreaksAreRemoved() throws {
        let info = try #require(parse("(;GC[A long comm\\\nent]C[wrapped\\\r\nline])").info)
        #expect(info.gameComment == "A long comment")
        #expect(info.commentText == "wrappedline")
    }

    // MARK: Results: anything not starting with "W+" counted as a Black win.

    @Test(arguments: ["0", "Draw", "Void", "?"])
    func drawsVoidAndUnknownResultsHaveNoWinner(result: String) throws {
        let info = try #require(parse("(;PB[Kuro]PW[Shiro]RE[\(result)])").info)
        #expect(info.winner == nil)
        #expect(info.loser == nil)
    }

    @Test func winsForEitherColor() throws {
        let white = try #require(parse("(;PB[Kuro]PW[Shiro]RE[W+0.5])").info)
        #expect(white.winner == "Shiro")
        #expect(white.loser == "Kuro")
        let black = try #require(parse("(;PB[Kuro]PW[Shiro]RE[B+Resign])").info)
        #expect(black.winner == "Kuro")
        #expect(black.loser == "Shiro")
    }

    // MARK: Setup stones: AB and AW anywhere in the first game were added; AE was ignored.

    @Test func setupStonesInAVariationDoNotLeak() throws {
        let game = try firstGame(Fixtures.variations)
        let position = game.position(afterMainLineMoves: 50)
        #expect(position[pt("aa")] == nil)
        #expect(position[pt("ab")] == nil)
    }

    @Test func setupStonesAfterTheOpeningDoNotLeak() throws {
        var text = "(;GM[1]SZ[19]"
        let columns = Array("abcdefghijklmnopqrs")
        for index in 0 ..< 60 {
            let color = index.isMultiple(of: 2) ? "B" : "W"
            text += ";\(color)[\(columns[index % 19])\(columns[index / 19 * 2])]"
        }
        text += ";AB[ss]AW[sr])"
        let game = try firstGame(text)
        let opening = game.position(afterMainLineMoves: 50)
        #expect(opening[pt("ss")] == nil)
        #expect(opening[pt("sr")] == nil)
        #expect(game.position(afterMainLineMoves: .max)[pt("ss")] == .black)
    }

    @Test func removedStonesAreRemoved() throws {
        let game = try firstGame("(;GM[1]SZ[19]AB[pd][dp][pp];AE[pp];W[dd])")
        #expect(game.position(afterMainLineMoves: 1).compactPosition == "19,dppd,dd")
    }

    // MARK: Rectangular boards: SZ[19:13] was not supported.

    @Test func rectangularBoard() throws {
        let collection = parse("(;GM[1]FF[4]SZ[19:13];B[pd];W[dj])")
        let info = try #require(collection.info)
        #expect(info.boardSize == BoardSize(columns: 19, rows: 13))
        #expect(collection.warnings.isEmpty)
        let game = try #require(collection.games.first)
        #expect(game.position(afterMainLineMoves: .max).compactPosition == "19:13,pd,dj")
    }

    // MARK: Dates: only an exact YYYY-MM-DD became Date Played.

    @Test func partialDates() throws {
        let month = try #require(parse("(;DT[2006-10])").info)
        #expect(month.datePlayed == PartialDate(year: 2006, month: 10))
        #expect(month.yearPlayed == 2006)
        let year = try #require(parse("(;DT[1846])").info)
        #expect(year.datePlayed == PartialDate(year: 1846))
        #expect(year.yearPlayed == 1846)
        let list = try #require(parse("(;DT[1846-09-11,12,14])").info)
        #expect(list.datePlayed == PartialDate(year: 1846, month: 9, day: 11))
    }

    // MARK: Game names: the GM list had typos.

    @Test func gameNamesAreSpelledCorrectly() throws {
        #expect(try #require(parse("(;GM[4])").info).gameTypeName == "Gomoku+Renju")
        #expect(try #require(parse("(;GM[29])").info).gameTypeName == "Hnefatafl")
    }
}
