import Foundation
import SGFKit
import Testing

@Suite("Spotlight attributes")
struct SpotlightAttributesTests {
    private typealias Name = SpotlightAttributes.Name
    private typealias Standard = SpotlightAttributes.Standard

    private func attributes(_ sgf: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> SpotlightAttributes {
        try #require(SpotlightAttributes(collection: collection(sgf)), sourceLocation: sourceLocation)
    }

    /// Noon UTC on a day, as Date Played stores it.
    private func noon(_ day: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: "\(day)T12:00:00Z"))
    }

    /// A made-up game with every property that is indexed.
    static let everyProperty = """
        (;GM[1]FF[4]CA[UTF-8]AP[FixtureWriter:1.0]SZ[19]KM[6.5]HA[0]RU[Japanese]OH[B-(W)-B]
        GN[Fixture game]PB[Black Tester]BR[3d]PW[White Tester]WR[4d]BT[Team Kuro]WT[Team Shiro]
        EV[Fixture Cup]RO[2 (final)]DT[2024-03-17]PC[Nowhere]RE[W+2.5]TM[3600]OT[5x30 byo-yomi]
        ON[Nirensei]SO[Invented]AN[Nobody]US[Tester]CP[Public domain]
        GC[A game made up for tests.
        It has two lines.]
        ;B[pd];W[dp]C[A comment.];B[pp];W[];B[dd]N[Corner])
        """

    @Test func everyAttributeOfOneGame() throws {
        let attributes = try attributes(Self.everyProperty)
        #expect(Set(attributes.values.keys) == Set(Standard.all + Name.all))

        #expect(attributes[Standard.title] == .string("Fixture game"))
        #expect(attributes[Standard.description] == .string("A game made up for tests.\nIt has two lines."))
        #expect(attributes[Standard.headline] == .string("W+2.5"))
        #expect(attributes[Standard.coverage] == .string("Fixture Cup"))
        #expect(attributes[Standard.authors] == .strings(["Tester"]))
        #expect(attributes[Standard.participants] == .strings(["Black Tester", "White Tester", "Team Kuro", "Team Shiro"]))
        #expect(attributes[Standard.contributors] == .strings(["Nobody"]))
        #expect(attributes[Standard.publishers] == .strings(["Invented"]))
        #expect(attributes[Standard.textContent] == .string("2024-03-17 A comment. Corner"))
        #expect(attributes[Standard.version] == .string("4"))
        #expect(attributes[Standard.creator] == .string("FixtureWriter:1.0"))
        #expect(attributes[Standard.copyright] == .string("Public domain"))
        #expect(attributes[Standard.namedLocation] == .string("Nowhere"))
        #expect(attributes[Standard.durationSeconds] == .real(3600))

        #expect(attributes[Name.black] == .string("Black Tester"))
        #expect(attributes[Name.white] == .string("White Tester"))
        #expect(attributes[Name.blackRank] == .string("3d"))
        #expect(attributes[Name.whiteRank] == .string("4d"))
        #expect(attributes[Name.blackTeam] == .string("Team Kuro"))
        #expect(attributes[Name.whiteTeam] == .string("Team Shiro"))
        #expect(attributes[Name.result] == .string("W+2.5"))
        #expect(attributes[Name.winner] == .string("White Tester"))
        #expect(attributes[Name.loser] == .string("Black Tester"))
        #expect(attributes[Name.event] == .string("Fixture Cup"))
        #expect(attributes[Name.round] == .string("2 (final)"))
        #expect(attributes[Name.datePlayed] == .date(try noon("2024-03-17")))
        #expect(attributes[Name.yearPlayed] == .integer(2024))
        #expect(attributes[Name.ruleset] == .string("Japanese"))
        #expect(attributes[Name.komi] == .real(6.5))
        #expect(attributes[Name.handicap] == .integer(0))
        #expect(attributes[Name.oldHandicap] == .string("B-(W)-B"))
        #expect(attributes[Name.overtime] == .string("5x30 byo-yomi"))
        #expect(attributes[Name.opening] == .string("Nirensei"))
        #expect(attributes[Name.gameType] == .string("Go"))
        #expect(attributes[Name.size] == .integer(19))
        #expect(attributes[Name.moves] == .integer(4), "the pass isn't counted")
        #expect(attributes[Name.numberOfGames] == .integer(1))
        #expect(attributes[Name.isCollection] == .boolean(false))
    }

    @Test func missingValuesAreLeftOut() throws {
        let attributes = try attributes("(;SZ[9];B[ee])")
        #expect(attributes.values == [
            Name.gameType: .string("Go"),
            Name.size: .integer(9),
            Name.moves: .integer(1),
            Name.numberOfGames: .integer(1),
            Name.isCollection: .boolean(false),
        ])
        #expect(try self.attributes("(;SZ[9]AB[ee])")[Name.moves] == .integer(0))
    }

    @Test func aFileWithNoGameHasNoAttributes() {
        #expect(SpotlightAttributes(collection: collection("Not a game at all.")) == nil)
    }

    @Test(arguments: [("B+R", "Kuro", "Shiro"), ("W+0.5", "Shiro", "Kuro"), ("b+t", "Kuro", "Shiro")])
    func winnerAndLoser(result: String, winner: String, loser: String) throws {
        let attributes = try attributes("(;PB[Kuro]PW[Shiro]RE[\(result)])")
        #expect(attributes[Name.winner] == .string(winner))
        #expect(attributes[Name.loser] == .string(loser))
    }

    /// 1.x made Black the winner of anything that didn't start with "W+".
    @Test(arguments: ["0", "Draw", "Jigo", "Void", "?", "Black won"])
    func noWinnerWithoutAWin(result: String) throws {
        let attributes = try attributes("(;PB[Kuro]PW[Shiro]RE[\(result)])")
        #expect(attributes[Name.result] == .string(result))
        #expect(attributes[Standard.headline] == .string(result))
        #expect(attributes[Name.winner] == nil)
        #expect(attributes[Name.loser] == nil)
    }

    @Test func datePlayedNeedsAFullDate() throws {
        let full = try attributes("(;DT[1996-05-06,07,20])")
        #expect(full[Name.datePlayed] == .date(try noon("1996-05-06")))
        #expect(full[Name.yearPlayed] == .integer(1996))
        #expect(full[Standard.textContent] == .string("1996-05-06,07,20"))

        for partial in ["1996-05", "1996", "Spring 1996 (Showa 71)"] {
            let attributes = try attributes("(;DT[\(partial)])")
            #expect(attributes[Name.datePlayed] == nil)
            #expect(attributes[Name.yearPlayed] == .integer(1996))
            #expect(attributes[Standard.textContent] == .string(partial))
        }
        #expect(try attributes("(;DT[unknown])")[Name.yearPlayed] == nil)
    }

    /// Noon UTC is the same day everywhere from UTC-11 to UTC+11, so Finder shows the day played.
    @Test func datePlayedIsTheSameDayInLocalTime() throws {
        let day = try #require(PartialDate(year: 1846, month: 7, day: 21))
        let date = try #require(SpotlightAttributes.day(of: day))
        for hours in -11 ... 11 {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: hours * 3600))
            #expect(calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: 1846, month: 7, day: 21))
        }
    }

    @Test(arguments: [
        ("(;SZ[13])", 13),
        ("(;GM[1])", 19),
        ("(;SZ[19:13])", 19),
        ("(;SZ[abc])", 19),
        ("(;GM[2]SZ[8])", 8),
        ("(;GM[3])", nil),
    ] as [(String, Int?)])
    func boardSize(sgf: String, expected: Int?) throws {
        #expect(try attributes(sgf)[Name.size] == expected.map(SpotlightAttributes.Value.integer))
    }

    @Test(arguments: [("(;SZ[19])", "Go"), ("(;GM[2]SZ[8])", "Othello"), ("(;GM[99])", nil)] as [(String, String?)])
    func gameType(sgf: String, expected: String?) throws {
        #expect(try attributes(sgf)[Name.gameType] == expected.map(SpotlightAttributes.Value.string))
    }

    @Test func movesLeaveOutPassesAndVariations() throws {
        let attributes = try attributes("(;SZ[9];B[ee];W[];B[tt];W[cc](;B[gg];W[jj])(;B[aa];W[bb];B[cc]))")
        #expect(attributes[Name.moves] == .integer(3))
    }

    /// The custom attributes describe the first game; the standard ones that 1.x collected from
    /// every game list each value once.
    @Test func collectionsListTheValuesOfEveryGame() throws {
        let attributes = try attributes("""
            (;GM[1]FF[4]SZ[9]GN[One]PB[Alpha]PW[Beta]EV[Club]RE[B+R]DT[2001-02-03]US[Tester]C[first];B[ee];W[cc])
            (;GM[1]FF[4]SZ[13]GN[Two]PB[Beta]PW[Gamma]EV[Club]RE[W+3.5]DT[2001-02-04]AN[Annotator]C[second])
            (;GM[1]FF[3]SZ[19]GN[Three]PB[Alpha]PW[Gamma]EV[Open]RE[Draw]SO[Magazine]US[Tester])
            """)
        #expect(attributes[Name.numberOfGames] == .integer(3))
        #expect(attributes[Name.isCollection] == .boolean(true))
        #expect(attributes[Name.black] == .string("Alpha"))
        #expect(attributes[Name.white] == .string("Beta"))
        #expect(attributes[Name.event] == .string("Club"))
        #expect(attributes[Name.winner] == .string("Alpha"))
        #expect(attributes[Name.size] == .integer(9))
        #expect(attributes[Name.moves] == .integer(2))
        #expect(attributes[Standard.version] == .string("4"))

        #expect(attributes[Standard.participants] == .strings(["Alpha", "Beta", "Gamma"]))
        #expect(attributes[Standard.title] == .string("One; Two; Three"))
        #expect(attributes[Standard.headline] == .string("B+R; W+3.5; Draw"))
        #expect(attributes[Standard.coverage] == .string("Club; Open"))
        #expect(attributes[Standard.authors] == .strings(["Tester"]))
        #expect(attributes[Standard.contributors] == .strings(["Annotator"]))
        #expect(attributes[Standard.publishers] == .strings(["Magazine"]))
        #expect(attributes[Standard.textContent] == .string("2001-02-03 first 2001-02-04 second"))
    }

    @Test func collectionReadOnlyToItsFirstGame() throws {
        let attributes = try #require(SpotlightAttributes(collection: collection("(;PB[One])(;PB[Two])", stopAfterFirstGame: true)))
        #expect(attributes[Name.isCollection] == .boolean(true))
        #expect(attributes[Standard.participants] == .strings(["One"]))
    }

    /// John Mifsud's 2009 game against GNU Go, from the 1.x test files, which has every property.
    @Test func johnVsGnu() throws {
        let attributes = try #require(try SpotlightAttributes(contentsOf: Fixtures.johnVsGnu()))
        #expect(Set(attributes.values.keys) == Set(Standard.all + Name.all))
        #expect(attributes[Name.black] == .string("John Mifsud"))
        #expect(attributes[Name.white] == .string("GNU Go"))
        #expect(attributes[Name.blackRank] == .string("15k"))
        #expect(attributes[Name.whiteRank] == .string("NR"))
        #expect(attributes[Name.result] == .string("B+17.5"))
        #expect(attributes[Name.winner] == .string("John Mifsud"))
        #expect(attributes[Name.loser] == .string("GNU Go"))
        #expect(attributes[Name.event] == .string("My So-Called Life"))
        #expect(attributes[Name.round] == .string("666 (league)"))
        #expect(attributes[Name.datePlayed] == .date(try noon("2009-12-10")))
        #expect(attributes[Name.yearPlayed] == .integer(2009))
        #expect(attributes[Name.handicap] == .integer(3))
        #expect(attributes[Name.komi] == .real(0.5))
        #expect(attributes[Name.oldHandicap] == .string("OH? I'm OG"))
        #expect(attributes[Name.moves] == .integer(232))
        #expect(attributes[Standard.title] == .string("John's Latest \"Triumph\""))
        #expect(attributes[Standard.participants] == .strings(["John Mifsud", "GNU Go", "BlackTeam", "WhiteTeam"]))
        #expect(attributes[Standard.namedLocation] == .string("My secret underground lair"))
        #expect(attributes[Standard.durationSeconds] == .real(999))
        #expect(attributes[Standard.textContent] == .string("2009-12-10 It has begun Victory Don't be too proud!"))
    }

    @Test func readsOnlyTheStartOfALargeFile() throws {
        let game = "(;GM[1]SZ[9]PB[Kuro]PW[Shiro];B[ee];W[cc])\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sgf")
        try Data(String(repeating: game, count: 100).utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let whole = try #require(try SpotlightAttributes(contentsOf: url))
        #expect(whole[Name.numberOfGames] == .integer(100))
        // Ten games and the start of the eleventh, up to its PB.
        let start = try #require(try SpotlightAttributes(contentsOf: url, byteLimit: game.utf8.count * 10 + 20))
        #expect(start[Name.numberOfGames] == .integer(11))
        #expect(start[Standard.participants] == .strings(["Kuro", "Shiro"]))
    }

    @Test func aMissingFileThrows() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sgf")
        #expect(throws: (any Error).self) { try SpotlightAttributes(contentsOf: url) }
    }

    /// The types Spotlight needs: a Boolean must be a `CFBoolean`, not a number.
    @Test func foundationObjects() {
        typealias Value = SpotlightAttributes.Value
        #expect(CFGetTypeID(Value.string("x").object as AnyObject) == CFStringGetTypeID())
        #expect(CFGetTypeID(Value.strings(["x"]).object as AnyObject) == CFArrayGetTypeID())
        #expect(CFGetTypeID(Value.integer(3).object as AnyObject) == CFNumberGetTypeID())
        #expect(CFGetTypeID(Value.real(6.5).object as AnyObject) == CFNumberGetTypeID())
        #expect(CFGetTypeID(Value.boolean(true).object as AnyObject) == CFBooleanGetTypeID())
        #expect(CFGetTypeID(Value.date(.now).object as AnyObject) == CFDateGetTypeID())
    }

    /// A made-up collection about the size of the largest SGF file found so far (1.78 MB, 4,002
    /// games), with 60 moves and a comment in each game, should be indexed quickly even in a
    /// debug build.
    @Test func fastEnough() throws {
        // The moves of a made-up game, without its "(;GM[1]FF[4]SZ[19]" and ")".
        let moves = String(longGame(size: 19, moves: 60).dropFirst(18).dropLast())
        var text = ""
        for index in 1 ... 4_000 {
            text += "(;GM[1]FF[4]SZ[19]PB[Black \(index)]PW[White \(index)]EV[Event \(index % 40)]"
            text += "DT[2001-01-\(index % 28 + 1)]RE[B+R]C[Comment on game \(index).]\n"
            text += moves + ")\n"
        }
        let data = Data(text.utf8)
        let clock = ContinuousClock()
        var attributes: SpotlightAttributes?
        let duration = clock.measure {
            attributes = SpotlightAttributes(collection: SGFParser.parse(data))
        }
        print("Spotlight attributes of \(data.count.formatted()) bytes, 4,000 games: \(duration)")
        #expect(attributes?[Name.numberOfGames] == .integer(4_000))
        #expect(duration < .seconds(3))
    }
}

@Suite("Spotlight schema")
struct SpotlightSchemaTests {
    private typealias Name = SpotlightAttributes.Name
    private typealias Standard = SpotlightAttributes.Standard

    /// The importer's source folder.
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Spotlight", isDirectory: true)

    private func schema() throws -> XMLDocument {
        try XMLDocument(contentsOf: Self.folder.appendingPathComponent("schema.xml"))
    }

    private func words(_ element: String, in schema: XMLDocument) throws -> [String] {
        let node = try #require(try schema.nodes(forXPath: "//*[local-name()='\(element)']").first)
        return (node.stringValue ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    @Test func declaresTheCustomAttributesWithTheirTypes() throws {
        let declared = try schema().nodes(forXPath: "//*[local-name()='attribute']").compactMap { $0 as? XMLElement }
        #expect(declared.compactMap { $0.attribute(forName: "name")?.stringValue } == Name.all)
        #expect(declared.allSatisfy { $0.attribute(forName: "multivalued")?.stringValue == "false" })

        // Every value the importer sets has the declared type.
        let types = Dictionary(uniqueKeysWithValues: declared.map {
            ($0.attribute(forName: "name")?.stringValue ?? "", $0.attribute(forName: "type")?.stringValue ?? "")
        })
        let attributes = try #require(SpotlightAttributes(collection: collection(SpotlightAttributesTests.everyProperty)))
        for name in Name.all {
            let value = try #require(attributes[name])
            let type = switch value {
            case .string: "CFString"
            case .integer, .real: "CFNumber"
            case .boolean: "CFBoolean"
            case .date: "CFDate"
            case .strings: "multivalued CFString"
            }
            #expect(types[name] == type, "\(name)")
        }
    }

    @Test func theTypeListsEveryAttribute() throws {
        let schema = try schema()
        let type = try #require(try schema.nodes(forXPath: "//*[local-name()='type']").first as? XMLElement)
        #expect(type.attribute(forName: "name")?.stringValue == "com.red-bean.sgf")
        let all = try words("allattrs", in: schema)
        #expect(all == Standard.all + Name.all)
        let shown = try words("displayattrs", in: schema)
        #expect(!shown.isEmpty)
        #expect(Set(shown).isSubset(of: all))
    }

    /// The `.lproj` folders with a `schema.strings`.
    static func languages() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(".lproj".count)) }
            .sorted()
    }

    private func names(in language: String) throws -> [String: String] {
        let url = Self.folder.appendingPathComponent("\(language).lproj/schema.strings")
        let list = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(list as? [String: String])
    }

    @Test func everyLanguageNamesAndDescribesEveryCustomAttribute() throws {
        let keys = Set(Name.all.flatMap { [$0, "\($0).Description"] })
        #expect(try Self.languages().contains("en"))
        for language in try Self.languages() {
            let names = try names(in: language)
            #expect(Set(names.keys) == keys, "\(language)")
            #expect(names.values.allSatisfy { !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespaces) }, "\(language)")
        }
    }

    @Test func englishNames() throws {
        let names = try names(in: "en")
        #expect(names[Name.black] == "Black Player")
        #expect(names[Name.yearPlayed] == "Year Played")
        #expect(names["\(Name.komi).Description"] == "Amount of komi the white player received")
    }

    /// English and the nine translations of 1.x.
    @Test func languages() throws {
        #expect(try Self.languages() == ["de", "en", "fr", "ja", "ko", "pl", "ru", "sv", "zh-Hans", "zh-Hant"])
    }

    /// Errors in the names of 1.x, fixed in 2.0.
    @Test func fixedTranslations() throws {
        #expect(try names(in: "fr")["\(Name.opening).Description"] == "Information sur l'ouverture utilisé")

        let japanese = try names(in: "ja")
        #expect(japanese[Name.size] == "碁盤のサイズ")
        #expect(japanese[Name.black] == "黒")
        #expect(japanese.values.allSatisfy { !$0.contains("黑") }, "the Japanese form of Black, not the Chinese one")

        let swedish = try names(in: "sv")
        #expect(swedish[Name.opening] == "Öppning")
        #expect(swedish[Name.ruleset] == "Regler")
    }
}
