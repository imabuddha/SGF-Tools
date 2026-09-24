import Foundation
import Testing
@testable import SGFKit

@Suite("Values: escapes, Text, and SimpleText")
struct ValueTextTests {
    @Test func escapedCloseBracketStaysInsideTheValue() throws {
        let game = try firstGame(#"(;C[a \] b]GN[x])"#)
        #expect(game.root["C"]?.value.raw == #"a \] b"#)
        #expect(game.root["C"]?.value.text == "a ] b")
        #expect(game.root["GN"]?.value.text == "x")
    }

    @Test func escapedBackslash() throws {
        let game = try firstGame(#"(;C[C:\\games\\]GN[x])"#)
        #expect(game.root["C"]?.value.text == #"C:\games\"#)
        #expect(game.root["GN"]?.value.text == "x")
    }

    @Test func anyEscapedCharacterIsKeptVerbatim() {
        #expect(SGFValue(raw: #"\a\:\["#).text == "a:[")
    }

    @Test(arguments: ["\n", "\r\n", "\n\r", "\r"])
    func softLineBreaksAreRemoved(lineBreak: String) {
        let value = SGFValue(raw: "one\\" + lineBreak + "two")
        #expect(value.text == "onetwo")
        #expect(value.simpleText == "onetwo")
    }

    @Test(arguments: ["\n", "\r\n", "\n\r", "\r"])
    func hardLineBreaksAreNormalized(lineBreak: String) {
        let value = SGFValue(raw: "one" + lineBreak + "two" + lineBreak + lineBreak + "three")
        #expect(value.text == "one\ntwo\n\nthree")
        #expect(value.simpleText == "one two  three")
    }

    @Test func otherWhitespaceBecomesSpaces() {
        let value = SGFValue(raw: "a\tb\u{0B}c\u{0C}d")
        #expect(value.text == "a b c d")
        #expect(value.simpleText == "a b c d")
    }

    @Test func textKeepsSurroundingWhitespace() {
        #expect(SGFValue(raw: "  indented\n").text == "  indented\n")
    }

    @Test func aTrailingLoneBackslashIsDropped() {
        #expect(SGFValue(raw: "abc\\").text == "abc")
    }

    @Test func nonASCIITextSurvives() throws {
        let game = try firstGame("(;CA[UTF-8]C[\u{9ED2}\u{756A} \u{2014} caf\u{E9}])")
        #expect(game.root["C"]?.value.text == "\u{9ED2}\u{756A} \u{2014} caf\u{E9}")
    }
}

@Suite("Values: composed, numbers, and reals")
struct ValueTypedTests {
    @Test func composedValueSplitsAtTheFirstUnescapedColon() throws {
        let parts = try #require(SGFValue(raw: #"aa:a\:b:c"#).composed)
        #expect(parts.first.raw == "aa")
        #expect(parts.second.raw == #"a\:b:c"#)
        #expect(parts.second.simpleText == "a:b:c")
    }

    @Test func composedValueSkipsAnEscapedColon() throws {
        let parts = try #require(SGFValue(raw: #"a\:b:c"#).composed)
        #expect(parts.first.simpleText == "a:b")
        #expect(parts.second.simpleText == "c")
    }

    @Test func notComposedWithoutAColon() {
        #expect(SGFValue(raw: "aa").composed == nil)
        #expect(SGFValue(raw: #"a\:b"#).composed == nil)
    }

    @Test(arguments: [("19", 19), (" 7 ", 7), ("+3", 3), ("-2", -2), ("0", 0)])
    func numbers(raw: String, expected: Int) {
        #expect(SGFValue(raw: raw).number == expected)
    }

    @Test(arguments: ["", "x", "1.5", "19:13"])
    func notNumbers(raw: String) {
        #expect(SGFValue(raw: raw).number == nil)
    }

    @Test(arguments: [("6.5", 6.5), ("0.50", 0.5), ("-3", -3.0), (" 7.5 ", 7.5), ("6,5", 6.5), ("+2.75", 2.75)])
    func reals(raw: String, expected: Double) {
        #expect(SGFValue(raw: raw).real == expected)
    }

    @Test(arguments: ["", "six", "6.5.5", "nan", "inf"])
    func notReals(raw: String) {
        #expect(SGFValue(raw: raw).real == nil)
    }
}
