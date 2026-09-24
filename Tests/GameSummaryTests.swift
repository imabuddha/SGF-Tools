import Foundation
import SGFKit
import Testing

@Suite("Game summary")
struct GameSummaryTests {
    private let english = Locale(identifier: "en_US")

    private func summary(_ sgf: String) throws -> GameSummary {
        try #require(GameSummary(collection: collection(sgf), locale: english))
    }

    @Test(arguments: [
        ("B+17.5", "Black won by 17.5 points"),
        ("W+2.5", "White won by 2.5 points"),
        ("W+1", "White won by 1 point"),
        ("B+3", "Black won by 3 points"),
        ("B+0.5", "Black won by half a point"),
        ("W+R", "White won by resignation"),
        ("W+Resign", "White won by resignation"),
        ("b+r", "Black won by resignation"),
        ("B+T", "Black won on time"),
        ("W+Time", "White won on time"),
        ("W+F", "White won by forfeit"),
        ("B+", "Black won"),
        ("B+ 3.5", "Black won by 3.5 points"),
        ("B+3,5", "Black won by 3.5 points"),
        ("W+Moon", "White won (Moon)"),
        ("W+1e2", "White won (1e2)"),
        ("W+0x10", "White won (0x10)"),
        ("0", "Draw"),
        ("Draw", "Draw"),
        ("Jigo", "Draw"),
        ("Void", "No result"),
        ("?", "Unknown result"),
        ("Black wins by 3", "Black wins by 3"),
    ])
    func resultWording(sgf: String, expected: String) throws {
        #expect(try summary("(;RE[\(sgf)])").result == expected)
    }

    @Test func noResultNoLine() throws {
        #expect(try summary("(;PB[A])").result == nil)
    }

    @Test func everyFieldInOrder() throws {
        let summary = try summary(Fixtures.fullInfo)
        #expect(summary.title == "Fixture game")
        #expect(summary.black == .init(name: "Black Tester 3d", team: "Team Kuro"))
        #expect(summary.white == .init(name: "White Tester 4d", team: "Team Shiro"))
        #expect(summary.result == "White won by 2.5 points")
        #expect(summary.fields.map(\.label) == ["Event", "Round", "Date", "Place", "Rules", "Komi", "Moves"])
        #expect(summary.fields.map(\.value)
            == ["Fixture Cup", "2", "March 17, 2024", "Nowhere", "Japanese", "6.5", "6"])
        #expect(summary.gameComment == "A game made up for tests.\nIt has two lines.")
    }

    @Test func fieldsTheFileLacksAreLeftOut() throws {
        let summary = try summary("(;SZ[9];B[ee])")
        #expect(summary.title == nil)
        #expect(summary.black == nil)
        #expect(summary.white == nil)
        #expect(summary.result == nil)
        #expect(summary.gameComment == nil)
        #expect(summary.fields == [.init(label: "Moves", value: "1")])
        #expect(try self.summary("(;SZ[9])").fields.isEmpty)
    }

    @Test func players() throws {
        #expect(try summary("(;PB[Only Name])").black == .init(name: "Only Name", team: nil))
        #expect(try summary("(;BR[5k])").black == .init(name: "5k", team: nil))
        #expect(try summary("(;WT[Some Team])").white == .init(name: "Unknown", team: "Some Team"))
        #expect(try summary("(;PB[ ])").black == nil)
    }

    @Test func handicap() throws {
        #expect(try summary("(;HA[3])").fields == [.init(label: "Handicap", value: "3 stones")])
        #expect(try summary("(;HA[0])").fields.isEmpty)
        #expect(try summary("(;HA[1])").fields.isEmpty)
    }

    @Test func komi() throws {
        #expect(try summary("(;KM[0])").fields == [.init(label: "Komi", value: "0")])
        #expect(try summary("(;KM[7])").fields == [.init(label: "Komi", value: "7")])
        #expect(try summary("(;KM[-5.5])").fields == [.init(label: "Komi", value: "-5.5")])
        #expect(try summary("(;KM[0.75])").fields == [.init(label: "Komi", value: "0.75")])
    }

    @Test(arguments: [
        ("2024-03-17", "March 17, 2024"),
        ("2024-03", "March 2024"),
        ("1996", "1996"),
        ("1996-05-06,07", "1996-05-06,07"),
        ("Spring 1850", "Spring 1850"),
    ])
    func dates(written: String, expected: String) {
        #expect(GameSummary.describeDate(written, locale: english) == expected)
    }

    @Test func collectionsCountTheirGames() throws {
        let sgf = "(;PB[One];B[aa])(;PB[Two])(;PB[Three])"
        let summary = try summary(sgf)
        #expect(summary.fields.last == .init(label: "Games", value: "3"))
        #expect(summary.black?.name == "One")
        // Read only up to the first game, the file is still known to hold several.
        let partial = try #require(GameSummary(collection: collection(sgf, stopAfterFirstGame: true), locale: english))
        #expect(partial.fields.last == .init(label: "Games", value: "Several"))
        #expect(try self.summary("(;PB[One])").fields.allSatisfy { $0.label != "Games" })
    }

    @Test func aFileWithNoGameHasNoSummary() {
        #expect(GameSummary(collection: collection("Not a game at all.")) == nil)
    }
}
