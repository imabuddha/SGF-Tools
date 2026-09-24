import Foundation
import Testing
@testable import SGFKit

@Suite("Encodings")
struct EncodingTests {
    // "José" in Latin-1 / Windows-1252 is 4A 6F 73 E9; in UTF-8 it is 4A 6F 73 C3 A9.

    @Test func utf8Declared() throws {
        let collection = parse(bytes: ascii("(;CA[UTF-8]PB[Jos") + [0xC3, 0xA9] + ascii("])"))
        let game = try #require(collection.games.first)
        #expect(game.root["PB"]?.value.simpleText == "Jos\u{E9}")
        #expect(game.encoding == .utf8)
        #expect(collection.warnings.isEmpty)
    }

    @Test(arguments: ["utf-8", "UTF8", " utf-8 "])
    func utf8DeclaredWithOtherSpellings(name: String) throws {
        let collection = parse(bytes: ascii("(;CA[\(name)]PB[Jos") + [0xC3, 0xA9] + ascii("])"))
        let game = try #require(collection.games.first)
        #expect(game.root["PB"]?.value.simpleText == "Jos\u{E9}")
        #expect(collection.warnings.isEmpty)
    }

    @Test(arguments: ["ISO-8859-1", "iso-8859-1", "ISO8859-1", "ISO_8859-1", "Latin1", "latin-1", "windows-1252"])
    func latin1Declared(name: String) throws {
        let collection = parse(bytes: ascii("(;CA[\(name)]PB[Jos") + [0xE9] + ascii("])"))
        let game = try #require(collection.games.first)
        #expect(game.root["PB"]?.value.simpleText == "Jos\u{E9}")
        #expect(collection.warnings.isEmpty)
    }

    @Test func latin1DeclaredDecodesWindows1252Punctuation() throws {
        // 0x92 is a right single quotation mark in Windows-1252 and a C1 control in strict
        // ISO-8859-1. Files that say Latin-1 but were written on Windows use it for apostrophes.
        let game = try firstGame(bytes: ascii("(;CA[ISO-8859-1]C[Black") + [0x92] + ascii("s move])"))
        #expect(game.root["C"]?.value.text == "Black\u{2019}s move")
    }

    @Test func utf8DeclaredButLatin1FallsBackToWindows1252() throws {
        let collection = parse(bytes: ascii("(;CA[UTF-8]PB[Jos") + [0xE9] + ascii("]C[na") + [0xEF] + ascii("ve])"))
        let game = try #require(collection.games.first)
        #expect(game.root["PB"]?.value.simpleText == "Jos\u{E9}")
        #expect(game.root["C"]?.value.text == "na\u{EF}ve")
        #expect(game.encoding == .windowsCP1252)
        #expect(collection.warnings.map(\.kind) == [.encodingFallback(declared: "UTF-8", used: "Windows-1252")])
    }

    @Test func noCharsetValidUTF8() throws {
        let collection = parse(bytes: ascii("(;PB[Jos") + [0xC3, 0xA9] + ascii("])"))
        let game = try #require(collection.games.first)
        #expect(game.root["PB"]?.value.simpleText == "Jos\u{E9}")
        #expect(game.encoding == .utf8)
        #expect(collection.warnings.isEmpty)
    }

    @Test func noCharsetInvalidUTF8FallsBackQuietly() throws {
        // Without CA, FF[4] says the default is Latin-1, so decoding it that way is not a surprise.
        let collection = parse(bytes: ascii("(;PB[Jos") + [0xE9] + ascii("])"))
        let game = try #require(collection.games.first)
        #expect(game.root["PB"]?.value.simpleText == "Jos\u{E9}")
        #expect(game.encoding == .windowsCP1252)
        #expect(collection.warnings.isEmpty)
    }

    @Test func latin1DeclaredButValidUTF8IsReadAsUTF8() throws {
        let collection = parse(bytes: ascii("(;CA[ISO-8859-1]PB[Jos") + [0xC3, 0xA9] + ascii("])"))
        let game = try #require(collection.games.first)
        #expect(game.root["PB"]?.value.simpleText == "Jos\u{E9}")
        #expect(game.encoding == .utf8)
        #expect(collection.warnings.map(\.kind) == [.encodingFallback(declared: "ISO-8859-1", used: "UTF-8")])
    }

    @Test func asciiOnlyFilesNeverWarn() throws {
        let collection = parse("(;CA[ISO-8859-1]PB[Jose])")
        #expect(collection.games.first?.encoding == .windowsCP1252)
        #expect(collection.warnings.isEmpty)
    }

    @Test func utf8ByteOrderMarkWithUTF8Content() throws {
        let collection = parse(bytes: [0xEF, 0xBB, 0xBF] + ascii("(;PB[Jos") + [0xC3, 0xA9] + ascii("])"))
        #expect(collection.games.first?.root["PB"]?.value.simpleText == "Jos\u{E9}")
        #expect(collection.warnings.isEmpty)
    }

    @Test func shiftJISWithABackslashTrailByte() throws {
        // U+8868 is 0x95 0x5C in Shift_JIS: its second byte is a backslash, which must not escape
        // the closing bracket. U+9ED2 (black) is 0x8D 0x95.
        let bytes = ascii("(;CA[Shift_JIS]PB[") + [0x8D, 0x95, 0x95, 0x5C] + ascii("]PW[W];B[aa])")
        let collection = parse(bytes: bytes)
        let game = try #require(collection.games.first)
        #expect(game.root["PB"]?.value.simpleText == "\u{9ED2}\u{8868}")
        #expect(game.root["PW"]?.value.simpleText == "W")
        #expect(game.nodes.count == 2)
        #expect(game.encoding == .shiftJIS)
        #expect(collection.warnings.isEmpty)
    }

    @Test func shiftJISRootPropertyBeforeTheCharset() throws {
        // The charset comes after a value whose trail byte is a backslash.
        let bytes = ascii("(;PB[") + [0x95, 0x5C] + ascii("]CA[SJIS];B[aa])")
        let game = try firstGame(bytes: bytes)
        #expect(game.root["PB"]?.value.simpleText == "\u{8868}")
        #expect(game.nodes.count == 2)
    }

    @Test func gbkWithABracketTrailByte() throws {
        // U+4E5A is 0x81 0x5D in GBK: its second byte is a closing bracket.
        let bytes = ascii("(;CA[GBK]C[") + [0x81, 0x5D] + ascii("];B[aa])")
        let game = try firstGame(bytes: bytes)
        #expect(game.root["C"]?.value.text == "\u{4E5A}")
        #expect(game.nodes.count == 2)
    }

    @Test func big5() throws {
        // U+529F is 0xA5 0x5C in Big5.
        let bytes = ascii("(;CA[Big5]C[") + [0xA5, 0x5C] + ascii("];B[aa])")
        let game = try firstGame(bytes: bytes)
        #expect(game.root["C"]?.value.text == "\u{529F}")
        #expect(game.nodes.count == 2)
    }

    @Test func eucKR() throws {
        // U+BC14 U+B451 ("baduk") is B9 D9 B5 CF in EUC-KR.
        let game = try firstGame(bytes: ascii("(;CA[EUC-KR]GN[") + [0xB9, 0xD9, 0xB5, 0xCF] + ascii("])"))
        #expect(game.root["GN"]?.value.simpleText == "\u{BC14}\u{B451}")
    }

    @Test func koi8R() throws {
        // U+0418 U+0433 U+043E is E9 C7 CF in KOI8-R.
        let game = try firstGame(bytes: ascii("(;CA[KOI8-R]GN[") + [0xE9, 0xC7, 0xCF] + ascii("])"))
        #expect(game.root["GN"]?.value.simpleText == "\u{0418}\u{0433}\u{043E}")
    }

    @Test func unknownCharsetFallsBackWithAWarning() throws {
        let collection = parse(bytes: ascii("(;CA[klingon-7]PB[Jos") + [0xC3, 0xA9] + ascii("])"))
        let game = try #require(collection.games.first)
        #expect(game.root["PB"]?.value.simpleText == "Jos\u{E9}")
        #expect(collection.warnings.map(\.kind) == [.unknownCharset("klingon-7")])
    }

    @Test func eachGameInACollectionHasItsOwnCharset() throws {
        let bytes = ascii("(;CA[UTF-8]PB[Jos") + [0xC3, 0xA9] + ascii("])")
            + ascii("(;CA[ISO-8859-1]PB[Jos") + [0xE9] + ascii("])")
        let collection = parse(bytes: bytes)
        #expect(collection.games.map { $0.root["PB"]?.value.simpleText } == ["Jos\u{E9}", "Jos\u{E9}"])
        #expect(collection.warnings.isEmpty)
    }
}
