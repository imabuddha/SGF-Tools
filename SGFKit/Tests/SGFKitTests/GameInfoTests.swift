import Foundation
import Testing
@testable import SGFKit

@Suite("Game info")
struct GameInfoTests {
    @Test func readsEveryField() throws {
        let info = GameInfo(game: try firstGame(Fixtures.game19))
        #expect(info.blackPlayer == "Black Tester")
        #expect(info.whitePlayer == "White Tester")
        #expect(info.blackRank == "3d")
        #expect(info.whiteRank == "4d")
        #expect(info.blackTeam == "Team Kuro")
        #expect(info.whiteTeam == "Team Shiro")
        #expect(info.result == "W+2.5")
        #expect(info.event == "Fixture Cup")
        #expect(info.round == "2")
        #expect(info.date == "2024-03-17")
        #expect(info.place == "Nowhere")
        #expect(info.rules == "Japanese")
        #expect(info.komi == 6.5)
        #expect(info.handicap == nil)
        #expect(info.timeLimit == 3600)
        #expect(info.overtime == "5x30 byo-yomi")
        #expect(info.opening == "Nirensei")
        #expect(info.source == "Invented")
        #expect(info.annotator == "Nobody")
        #expect(info.user == "Tester")
        #expect(info.application == "FixtureWriter:1.0")
        #expect(info.copyright == "Public domain")
        #expect(info.gameName == "Fixture game")
        #expect(info.gameComment == "A game made up for tests.")
        #expect(info.gameType == 1)
        #expect(info.gameTypeName == "Go")
        #expect(info.fileFormat == 4)
        #expect(info.boardSize == .standard)
    }

    @Test func derivedValues() throws {
        let info = GameInfo(game: try firstGame(Fixtures.game19))
        #expect(info.outcome == .win(.white, margin: "2.5"))
        #expect(info.winner == "White Tester")
        #expect(info.loser == "Black Tester")
        #expect(info.datePlayed == PartialDate(year: 2024, month: 3, day: 17))
        #expect(info.yearPlayed == 2024)
        #expect(info.moveCountWithoutPasses == 24)
        #expect(info.numberOfGames == 1)
        #expect(info.isCollection == false)
        #expect(info.commentText == "Both sides take corners. Approach A variation.")
    }

    @Test func handicapAndKomi() throws {
        let info = GameInfo(game: try firstGame(Fixtures.handicap))
        #expect(info.handicap == 2)
        #expect(info.komi == 0.5)
        #expect(info.winner == "Black")
        #expect(info.loser == "White")
        #expect(info.outcome == .win(.black, margin: "R"))
    }

    @Test func oldHandicap() throws {
        let info = GameInfo(game: try firstGame("(;PB[Kuro]PW[Shiro]OH[ B-(W)-B ])"))
        #expect(info.oldHandicap == "B-(W)-B")
    }

    @Test func missingFieldsAreNil() throws {
        let info = GameInfo(game: try firstGame("(;SZ[9];B[ee])"))
        #expect(info.blackPlayer == nil)
        #expect(info.result == nil)
        #expect(info.outcome == nil)
        #expect(info.winner == nil)
        #expect(info.datePlayed == nil)
        #expect(info.yearPlayed == nil)
        #expect(info.komi == nil)
        #expect(info.oldHandicap == nil)
        #expect(info.gameType == 1)
        #expect(info.gameTypeName == "Go")
        #expect(info.fileFormat == nil)
        #expect(info.commentText == "")
        #expect(info.boardSize == BoardSize(9))
    }

    @Test func emptyAndBlankValuesAreNil() throws {
        let info = GameInfo(game: try firstGame("(;PB[]PW[  ]EV[\n]RE[])"))
        #expect(info.blackPlayer == nil)
        #expect(info.whitePlayer == nil)
        #expect(info.event == nil)
        #expect(info.result == nil)
    }

    @Test func simpleTextFieldsAreTrimmedAndUnescaped() throws {
        let info = GameInfo(game: try firstGame(#"(;PB[ Honinbo \] Shusaku ]EV[The\#nCup])"#))
        #expect(info.blackPlayer == "Honinbo ] Shusaku")
        #expect(info.event == "The Cup")
    }

    @Test func gameCommentKeepsLineBreaks() throws {
        let info = GameInfo(game: try firstGame("(;GC[line one\nline two])"))
        #expect(info.gameComment == "line one\nline two")
    }

    @Test func gameInfoLaterOnTheMainLine() throws {
        let info = GameInfo(game: try firstGame("(;SZ[9];PB[Late]EV[Found];B[ee](;W[cc])(;PW[Variation only]))"))
        #expect(info.blackPlayer == "Late")
        #expect(info.event == "Found")
        #expect(info.whitePlayer == nil)
    }

    @Test(arguments: [
        ("B+R", GameResult.win(.black, margin: "R")),
        ("W+Resign", .win(.white, margin: "Resign")),
        ("w+3.5", .win(.white, margin: "3.5")),
        (" B+T ", .win(.black, margin: "T")),
        ("B+", .win(.black, margin: "")),
        ("0", .draw),
        ("Draw", .draw),
        ("draw", .draw),
        ("Jigo", .draw),
        ("Void", .void),
        ("void", .void),
        ("?", .unknown),
        ("Black won", .unknown),
        ("", .unknown),
    ])
    func results(sgf: String, expected: GameResult) {
        #expect(GameResult(sgf: sgf) == expected)
    }

    @Test func winnerColor() {
        #expect(GameResult.win(.black, margin: "R").winner == .black)
        #expect(GameResult.draw.winner == nil)
    }

    @Test(arguments: ["0", "Draw", "Void", "?"])
    func noWinnerWithoutAWin(result: String) throws {
        let info = GameInfo(game: try firstGame("(;PB[Kuro]PW[Shiro]RE[\(result)])"))
        #expect(info.winner == nil)
        #expect(info.loser == nil)
    }

    @Test func noWinnerNameWithoutPlayers() throws {
        let info = GameInfo(game: try firstGame("(;PB[Kuro]RE[W+R])"))
        #expect(info.outcome == .win(.white, margin: "R"))
        #expect(info.winner == nil)
        #expect(info.loser == "Kuro")
    }

    @Test func moveCountWithoutPassesSkipsPassesVariationsAndLaterGames() throws {
        let text = "(;SZ[9];B[ee];W[];B[tt];W[cc](;B[gg];W[jj])(;B[aa];W[bb];B[cc]))(;SZ[9];B[aa];W[bb];B[cc];W[dd])"
        let info = try #require(parse(text).info)
        #expect(info.moveCountWithoutPasses == 3)
    }

    @Test func collectionInfo() throws {
        let info = try #require(parse(Fixtures.collection).info)
        #expect(info.numberOfGames == 3)
        #expect(info.isCollection)
        #expect(info.blackPlayer == "First Black")
        #expect(info.whitePlayer == "First White")
        #expect(info.boardSize == BoardSize(9))
        #expect(info.moveCountWithoutPasses == 2)
        #expect(info.commentText == "one two three")
    }

    @Test func collectionInfoWhenStoppingAfterTheFirstGame() throws {
        let info = try #require(parse(Fixtures.collection, options: .init(stopAfterFirstGame: true)).info)
        #expect(info.isCollection)
        #expect(info.numberOfGames == 1)
        #expect(info.commentText == "one two")
    }

    @Test func noInfoWithoutGames() {
        #expect(parse("nothing").info == nil)
    }

    @Test func commentTextJoinsLinesWithSpaces() throws {
        let info = GameInfo(game: try firstGame("(;C[first\nline\r\nsecond];N[name\\\nd]C[\tlast])"))
        #expect(info.commentText == "first line second named last")
    }

    @Test(arguments: [
        (1, "Go"), (2, "Othello"), (3, "Chess"), (4, "Gomoku+Renju"), (5, "Nine Men's Morris"),
        (7, "Chinese Chess"), (27, "Hive"), (29, "Hnefatafl"), (40, "Kropki"),
    ])
    func gameTypeNames(number: Int, name: String) throws {
        let info = GameInfo(game: try firstGame("(;GM[\(number)])"))
        #expect(info.gameType == number)
        #expect(info.gameTypeName == name)
    }

    @Test(arguments: ["0", "41", "x", "-9223372036854775808", "9223372036854775807"])
    func unknownGameTypes(value: String) throws {
        let info = GameInfo(game: try firstGame("(;GM[\(value)])"))
        #expect(info.gameTypeName == nil)
    }
}

@Suite("Dates")
struct PartialDateTests {
    @Test(arguments: [
        ("2024-03-17", PartialDate(year: 2024, month: 3, day: 17)),
        ("2006-10", PartialDate(year: 2006, month: 10)),
        ("1985", PartialDate(year: 1985)),
        ("1996-05-06,07,20", PartialDate(year: 1996, month: 5, day: 6)),
        ("1996-12-27,1997-01-03", PartialDate(year: 1996, month: 12, day: 27)),
        ("1996-05,06", PartialDate(year: 1996, month: 5)),
        ("  2001-02-03 ", PartialDate(year: 2001, month: 2, day: 3)),
        ("2001/02/03", PartialDate(year: 2001, month: 2, day: 3)),
        ("2001.2.3", PartialDate(year: 2001, month: 2, day: 3)),
        ("Played in 1941", PartialDate(year: 1941)),
        ("1941 (Showa 16)", PartialDate(year: 1941)),
        ("2024-13-01", PartialDate(year: 2024)),
        ("2023-02-29", PartialDate(year: 2023, month: 2)),
        ("2024-02-29", PartialDate(year: 2024, month: 2, day: 29)),
        ("12345-01-01", nil),
        ("", nil),
        ("unknown", nil),
        ("03/05/41", nil),
    ])
    func parsesTheFirstDate(sgf: String, expected: PartialDate?) {
        #expect(PartialDate(sgfDate: sgf) == expected)
    }

    @Test func description() {
        #expect(PartialDate(year: 2024, month: 3, day: 7)?.description == "2024-03-07")
        #expect(PartialDate(year: 2006, month: 10)?.description == "2006-10")
        #expect(PartialDate(year: 985)?.description == "0985")
    }

    @Test func invalidComponents() {
        #expect(PartialDate(year: 2024, month: 0) == nil)
        #expect(PartialDate(year: 2024, month: 4, day: 31) == nil)
        #expect(PartialDate(year: 2024, day: 3) == nil)
        #expect(PartialDate(year: 10_000) == nil)
    }

    @Test func dateComponents() throws {
        let components = try #require(PartialDate(year: 2006, month: 10)).dateComponents
        #expect(components.year == 2006)
        #expect(components.month == 10)
        #expect(components.day == nil)
    }

    @Test func infoUsesThePartialDate() throws {
        let info = GameInfo(game: try firstGame("(;DT[2006-10])"))
        #expect(info.datePlayed == PartialDate(year: 2006, month: 10))
        #expect(info.yearPlayed == 2006)
        #expect(info.date == "2006-10")
    }
}
