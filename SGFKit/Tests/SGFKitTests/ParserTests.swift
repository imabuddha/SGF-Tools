import Foundation
import Testing
@testable import SGFKit

@Suite("Parser: structure")
struct ParserStructureTests {
    @Test func parsesASimpleGame() throws {
        let collection = parse("(;GM[1]FF[4]SZ[9];B[ee];W[cc])")
        #expect(collection.games.count == 1)
        #expect(collection.warnings.isEmpty)
        let game = try #require(collection.games.first)
        #expect(game.nodes.count == 3)
        #expect(game.root["SZ"]?.value.raw == "9")
        #expect(game.root.properties.map(\.identifier) == ["GM", "FF", "SZ"])
        #expect(game.mainLine.map(\.id) == [0, 1, 2])
        #expect(game.mainLine[1]["B"]?.value.raw == "ee")
        #expect(game.mainLine[2]["W"]?.value.raw == "cc")
    }

    @Test func ignoresWhitespaceAndLineEndingsBetweenTokens() throws {
        let game = try firstGame("(\r\n ; GM [1]\tSZ\n[9]\r\n;\nB [ee] \n)\n")
        #expect(game.nodes.count == 2)
        #expect(game.root["GM"]?.value.raw == "1")
        #expect(game.root["SZ"]?.value.raw == "9")
        #expect(game.mainLine[1]["B"]?.value.raw == "ee")
    }

    @Test func keepsMultipleValues() throws {
        let game = try firstGame("(;AB[aa][bb] [cc]\n[dd])")
        #expect(game.root["AB"]?.values.map(\.raw) == ["aa", "bb", "cc", "dd"])
    }

    @Test func buildsTheVariationTree() throws {
        let game = try firstGame(Fixtures.variations)
        // Root, B E5, then three variations: (W, B), (W, B), (W).
        #expect(game.nodes.count == 7)
        let afterFirstMove = game.mainLine[1]
        let children = game.children(of: afterFirstMove)
        #expect(children.map { $0["W"]?.value.raw } == ["cc", "gc", "cg"])
        for child in children {
            #expect(game.parent(of: child)?.id == afterFirstMove.id)
        }
        #expect(game.parent(of: game.root) == nil)
        #expect(game.mainLine.compactMap { ($0["B"] ?? $0["W"])?.value.raw } == ["ee", "cc", "gg"])
    }

    @Test func nodesAreInDocumentOrder() throws {
        let game = try firstGame(Fixtures.variations)
        let moves = game.nodes.compactMap { ($0["B"] ?? $0["W"])?.value.raw }
        #expect(moves == ["ee", "cc", "gg", "gc", "cg", "cg"])
        for (index, node) in game.nodes.enumerated() {
            #expect(node.id == index)
        }
    }

    @Test func toleratesVariationsWithoutALeadingSequence() throws {
        // "(;a((;b)(;c)))": an extra pair of parentheses around the variations.
        let game = try firstGame("(;SZ[9]((;B[aa])(;B[bb])))")
        #expect(game.children(of: game.root).map { $0["B"]?.value.raw } == ["aa", "bb"])
    }

    @Test func parsesACollection() {
        let collection = parse(Fixtures.collection)
        #expect(collection.games.count == 3)
        #expect(collection.games.map { $0.root["SZ"]?.value.raw } == ["9", "13", "19"])
        #expect(collection.moreGamesFollow == false)
        #expect(collection.isCollection)
    }

    @Test func canStopAfterTheFirstGame() {
        let collection = parse(Fixtures.collection, options: .init(stopAfterFirstGame: true))
        #expect(collection.games.count == 1)
        #expect(collection.games.first?.root["PB"]?.value.raw == "First Black")
        #expect(collection.moreGamesFollow)
        #expect(collection.isCollection)
    }

    @Test func stoppingAfterTheFirstGameOfASingleGameFile() {
        let collection = parse(Fixtures.game19, options: .init(stopAfterFirstGame: true))
        #expect(collection.games.count == 1)
        #expect(collection.moreGamesFollow == false)
        #expect(collection.isCollection == false)
    }

    @Test func mergesARepeatedPropertyWithAWarning() throws {
        let collection = parse("(;AB[aa]SZ[9]AB[bb])")
        let game = try #require(collection.games.first)
        #expect(game.root["AB"]?.values.map(\.raw) == ["aa", "bb"])
        #expect(game.root.properties.map(\.identifier) == ["AB", "SZ"])
        #expect(collection.warnings.map(\.kind) == [.duplicateProperty("AB")])
    }

    @Test func emptyNodesAreKept() throws {
        let game = try firstGame("(;;;B[aa])")
        #expect(game.nodes.count == 3)
        #expect(game.root.properties.isEmpty)
    }

    @Test func emptyInputGivesNoGames() {
        #expect(parse("").games.isEmpty)
        #expect(parse(bytes: []).games.isEmpty)
        #expect(parse("   \n").warnings.isEmpty)
        #expect(parse("no game here").games.isEmpty)
    }

    @Test func handlesDeepVariationNestingWithoutRecursion() throws {
        let depth = 20_000
        let text = "(;SZ[19]" + String(repeating: "(;B[aa]", count: depth)
            + String(repeating: ")", count: depth) + ")"
        let game = try firstGame(text)
        #expect(game.nodes.count == depth + 1)
        #expect(game.mainLine.count == depth + 1)
    }

    @Test func handlesAVeryLongMainLine() throws {
        let moves = 100_000
        var text = "(;SZ[19]"
        for index in 0 ..< moves {
            text += index.isMultiple(of: 2) ? ";B[aa]" : ";W[tt]"
        }
        text += ")"
        let game = try firstGame(text)
        #expect(game.nodes.count == moves + 1)
        #expect(game.mainLine.count == moves + 1)
    }
}

@Suite("Parser: property identifiers")
struct ParserIdentifierTests {
    @Test func ignoresLowercaseLettersInIdentifiers() throws {
        let game = try firstGame(Fixtures.ff3)
        #expect(game.root.properties.map(\.identifier) == ["GM", "FF", "SZ", "PB", "PW", "AB"])
        #expect(game.root["AB"]?.values.map(\.raw) == ["cc", "gg"])
        #expect(game.mainLine.dropFirst().compactMap { ($0["B"] ?? $0["W"])?.value.raw }
            == ["ee", "tt", "ge"])
    }

    @Test func skipsAnAllLowercaseIdentifierWithAWarning() throws {
        let collection = parse("(;SZ[9]foo[bar]B[aa])")
        let game = try #require(collection.games.first)
        #expect(game.root.properties.map(\.identifier) == ["SZ", "B"])
        #expect(collection.warnings.map(\.kind) == [.invalidPropertyIdentifier("foo")])
    }

    @Test func warnsAboutAnIdentifierWithoutValues() throws {
        let collection = parse("(;SZ[9]KO;B[aa])")
        let game = try #require(collection.games.first)
        #expect(game.root.properties.map(\.identifier) == ["SZ"])
        #expect(game.nodes.count == 2)
        #expect(collection.warnings.map(\.kind) == [.missingValue(property: "KO")])
    }
}

@Suite("Parser: leading and trailing text")
struct ParserJunkTests {
    @Test func skipsAUTF8ByteOrderMarkSilently() throws {
        let collection = parse(bytes: [0xEF, 0xBB, 0xBF] + ascii("(;GM[1]SZ[9];B[aa])"))
        #expect(collection.games.count == 1)
        #expect(collection.warnings.isEmpty)
    }

    @Test func skipsTextBeforeTheFirstGameTree() throws {
        let collection = parse("Saved from a web page (see below).\n\n(;GM[1]SZ[9];B[aa])")
        #expect(collection.games.count == 1)
        #expect(collection.games.first?.nodes.count == 2)
        #expect(collection.warnings.map(\.kind) == [.skippedText(byteCount: 34)])
        #expect(collection.warnings.first?.offset == 0)
    }

    @Test func skipsAnOpeningParenthesisThatIsNotFollowedByANode() throws {
        let collection = parse("( (\n; GM[1])")
        #expect(collection.games.count == 1)
        #expect(collection.games.first?.root["GM"]?.value.raw == "1")
    }

    @Test func skipsTextBetweenAndAfterGames() {
        let collection = parse("(;SZ[9])\n-- next --\n(;SZ[13])\n-- end --\n")
        #expect(collection.games.map { $0.root["SZ"]?.value.raw } == ["9", "13"])
        #expect(collection.warnings.map(\.kind) == [.skippedText(byteCount: 10), .skippedText(byteCount: 9)])
    }
}

@Suite("Parser: malformed input")
struct ParserMalformedTests {
    @Test func missingCloseParenthesis() throws {
        let collection = parse("(;SZ[9];B[aa];W[bb]")
        let game = try #require(collection.games.first)
        #expect(game.nodes.count == 3)
        #expect(collection.warnings.map(\.kind) == [.missingCloseParenthesis(count: 1)])
    }

    @Test func missingSeveralCloseParentheses() throws {
        let collection = parse("(;SZ[9];B[aa](;W[bb](;B[cc]")
        let game = try #require(collection.games.first)
        #expect(game.nodes.count == 4)
        #expect(collection.warnings.map(\.kind) == [.missingCloseParenthesis(count: 3)])
    }

    @Test func strayCloseBracket() throws {
        let collection = parse("(;SZ[9]];B[aa])")
        let game = try #require(collection.games.first)
        #expect(game.nodes.count == 2)
        #expect(game.mainLine[1]["B"]?.value.raw == "aa")
        #expect(collection.warnings.map(\.kind) == [.unexpectedCharacter("]")])
        #expect(collection.warnings.first?.offset == 7)
    }

    @Test func truncatedInsideAValue() throws {
        let collection = parse("(;SZ[9];B[aa]C[unfinished comm")
        let game = try #require(collection.games.first)
        #expect(game.mainLine[1]["C"]?.value.text == "unfinished comm")
        #expect(collection.warnings.map(\.kind)
            == [.unterminatedValue(property: "C"), .missingCloseParenthesis(count: 1)])
    }

    @Test func truncatedInsideAnIdentifier() throws {
        let collection = parse("(;SZ[9];B[aa];W")
        let game = try #require(collection.games.first)
        #expect(game.nodes.count == 3)
        #expect(collection.warnings.map(\.kind)
            == [.missingValue(property: "W"), .missingCloseParenthesis(count: 1)])
    }

    @Test func truncatedAfterAnEscape() throws {
        let collection = parse("(;C[abc\\")
        let game = try #require(collection.games.first)
        #expect(game.root["C"]?.value.text == "abc")
    }

    @Test func extraCloseParenthesisAfterTheGame() {
        let collection = parse("(;SZ[9];B[aa]))")
        #expect(collection.games.count == 1)
        #expect(collection.warnings.map(\.kind) == [.skippedText(byteCount: 1)])
    }

    @Test func everyTruncationOfAGameParsesWithoutCrashing() {
        let bytes = ascii(Fixtures.game19)
        for length in 0 ... bytes.count {
            let collection = parse(bytes: Array(bytes[..<length]))
            #expect(collection.games.count <= 1)
            if let game = collection.games.first {
                _ = game.position(afterMainLineMoves: .max)
            }
        }
    }

    @Test func randomMutationsParseWithoutCrashing() {
        var generator = SeededGenerator(seed: 0x5EED)
        let original = ascii(Fixtures.game19 + Fixtures.collection + Fixtures.variations)
        let alphabet = ascii("()[];\\:ABWabtz \n") + [0x00, 0x80, 0xC3, 0xFF]
        for _ in 0 ..< 2_000 {
            var bytes = original
            for _ in 0 ..< Int.random(in: 1 ... 8, using: &generator) {
                let index = Int.random(in: 0 ..< bytes.count, using: &generator)
                switch Int.random(in: 0 ..< 3, using: &generator) {
                case 0: bytes[index] = alphabet.randomElement(using: &generator)!
                case 1: bytes.remove(at: index)
                default: bytes.insert(alphabet.randomElement(using: &generator)!, at: index)
                }
            }
            let collection = parse(bytes: bytes)
            for game in collection.games {
                _ = game.position(afterMainLineMoves: .max)
            }
        }
    }

    @Test func randomBytesParseWithoutCrashing() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0 ..< 500 {
            let count = Int.random(in: 0 ..< 400, using: &generator)
            var bytes = (0 ..< count).map { _ in UInt8.random(in: 0 ... 255, using: &generator) }
            if count > 2 { bytes.replaceSubrange(0 ..< 2, with: ascii("(;")) }
            let collection = parse(bytes: bytes)
            for game in collection.games {
                _ = game.position(afterMainLineMoves: .max)
            }
        }
    }
}

@Suite("Parser: UTF-16 input")
struct ParserUTF16Tests {
    @Test(arguments: [String.Encoding.utf16LittleEndian, .utf16BigEndian])
    func readsUTF16WithAByteOrderMark(encoding: String.Encoding) throws {
        let text = "(;GM[1]SZ[9]PB[Jos\u{E9}];B[ee])"
        let bom: [UInt8] = encoding == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]
        let bytes = bom + Array(try #require(text.data(using: encoding)))
        let game = try firstGame(bytes: bytes)
        #expect(game.root["PB"]?.value.simpleText == "Jos\u{E9}")
        #expect(game.mainLine.count == 2)
    }

    @Test func readsUTF16WithoutAByteOrderMark() throws {
        let text = "(;GM[1]SZ[9]PB[Jos\u{E9}];B[ee])"
        let bytes = Array(try #require(text.data(using: .utf16LittleEndian)))
        let game = try firstGame(bytes: bytes)
        #expect(game.root["PB"]?.value.simpleText == "Jos\u{E9}")
    }
}

/// A small deterministic random number generator (SplitMix64), so fuzz tests are repeatable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
