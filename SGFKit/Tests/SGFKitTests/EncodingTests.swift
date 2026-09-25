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

    @Test(arguments: ["\n", "\r\n", "\n\r", "\r"])
    func aSoftLineBreakInsideAUTF8Character(lineBreak: String) throws {
        // Programs that wrap long lines with soft line breaks (a backslash before a line break)
        // by counting bytes can put one inside a character: here inside "é" (C3 A9) and "が"
        // (E3 81 8C). The game must still be read as UTF-8, not in a charset detected for it.
        let softBreak = ascii("\\" + lineBreak)
        let bytes = ascii("(;GM[1]CA[UTF-8]C[Black: j'ai d") + [0xC3] + softBreak + [0xA9]
            + ascii("j\u{E0} vu \u{E7}a]GC[\u{3042}\u{308A}") + [0xE3, 0x81] + softBreak + [0x8C]
            + ascii("\u{3068}\u{3046}];B[pd])")
        let collection = parse(bytes: bytes)
        let game = try #require(collection.games.first)
        #expect(game.root["C"]?.value.text == "Black: j'ai d\u{E9}j\u{E0} vu \u{E7}a")
        #expect(game.root["GC"]?.value.text == "\u{3042}\u{308A}\u{304C}\u{3068}\u{3046}")
        #expect(game.encoding == .utf8)
        #expect(collection.warnings.isEmpty)
    }

    @Test func removingSoftLineBreaksKeepsOtherEscapes() throws {
        // "C:\\" ends in an escaped backslash, so the line break after it is a hard one.
        let bytes = ascii("(;C[C:\\\\\ncaf") + [0xC3] + ascii("\\\n") + [0xA9] + ascii(" \\] \\\\ \\:];B[pd])")
        let game = try firstGame(bytes: bytes)
        #expect(game.root["C"]?.value.text == "C:\\\ncaf\u{E9} ] \\ :")
        #expect(game.encoding == .utf8)
    }

    @Test func aSoftLineBreakInsideAUTF8CharacterOfALatin1Game() throws {
        // Declared Latin-1, but the text is UTF-8, as before, once the character is joined.
        let collection = parse(bytes: ascii("(;CA[ISO-8859-1]PB[Jos") + [0xC3] + ascii("\\\n") + [0xA9] + ascii("])"))
        let game = try #require(collection.games.first)
        #expect(game.root["PB"]?.value.simpleText == "Jos\u{E9}")
        #expect(game.encoding == .utf8)
        #expect(collection.warnings.map(\.kind) == [.encodingFallback(declared: "ISO-8859-1", used: "UTF-8")])
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

    // MARK: Detection, when the text should be UTF-8 but isn't

    @Test func rightQuoteInAChineseCharsetInsideASCIIText() throws {
        // A1 AF is the right single quotation mark in GBK and CP949. Files from Chinese and
        // Korean servers use it for apostrophes in English text; read as Windows-1252 it was
        // "\u{A1}\u{AF}".
        let collection = parse(bytes: ascii("(;GM[1]PB[Lee]C[Black") + [0xA1, 0xAF] + ascii("s move is good.];B[aa])"))
        let game = try #require(collection.games.first)
        #expect(game.root["C"]?.value.text == "Black\u{2019}s move is good.")
        #expect([CharsetDetection.gb18030, CharsetDetection.cp949].contains(game.encoding))
        #expect(collection.warnings.isEmpty)
    }

    @Test func koreanNamesInEUCKR() throws {
        // Detection needs a little text: two short names alone are sometimes taken for Big5 or
        // GBK, but a game record's usual fields are enough.
        let bytes = ascii("(;GM[1]EV[") + encoded("한국바둑리그", .EUC_KR) + ascii("]PB[")
            + encoded("김민준", .EUC_KR) + ascii("]PW[") + encoded("박서연", .EUC_KR) + ascii("]RE[")
            + encoded("백 불계승", .EUC_KR) + ascii("];B[pd])")
        let game = try firstGame(bytes: bytes)
        #expect(game.root["PB"]?.value.simpleText == "김민준")
        #expect(game.root["PW"]?.value.simpleText == "박서연")
        #expect(game.root["RE"]?.value.simpleText == "백 불계승")
        #expect(game.encoding == CharsetDetection.cp949)
    }

    @Test func japaneseNameInShiftJIS() throws {
        // The last character of the event, U+8868, is 95 5C: its trail byte is a backslash, so
        // the tree must be parsed again once Shift_JIS is detected, or the closing bracket
        // would be read as escaped.
        let bytes = ascii("(;GM[1]EV[") + encoded("日本代表", String.Encoding.shiftJIS) + ascii("]PB[")
            + encoded("山田太郎", String.Encoding.shiftJIS) + ascii("]PW[White];B[pd];W[dp])")
        let collection = parse(bytes: bytes)
        let game = try #require(collection.games.first)
        #expect(game.root["EV"]?.value.simpleText == "日本代表")
        #expect(game.root["PB"]?.value.simpleText == "山田太郎")
        #expect(game.root["PW"]?.value.simpleText == "White")
        #expect(game.nodes.count == 3)
        #expect(game.encoding == CharsetDetection.cp932)
        #expect(collection.warnings.isEmpty)
    }

    @Test(arguments: [
        ("张三", CFStringEncodings.GB_18030_2000, CharsetDetection.gb18030),
        ("圍棋比賽", CFStringEncodings.big5, CharsetDetection.big5),
    ])
    func chineseText(text: String, charset: CFStringEncodings, expected: String.Encoding) throws {
        let game = try firstGame(bytes: ascii("(;GM[1]EV[") + encoded(text, charset) + ascii("])"))
        #expect(game.root["EV"]?.value.simpleText == text)
        #expect(game.encoding == expected)
    }

    @Test func westernWindows1252TextDecodesAsBefore() throws {
        let players = "Émile Ängelholm"
        let comment = "l’été à Zürich — naïve café, Øyvind’s “Æsir” ½ point"
        for declaration in ["", "CA[UTF-8]"] {
            let bytes = ascii("(;GM[1]\(declaration)PB[") + encoded(players, .windowsCP1252)
                + ascii("]C[") + encoded(comment, .windowsCP1252) + ascii("])")
            let collection = parse(bytes: bytes)
            let game = try #require(collection.games.first)
            #expect(game.root["PB"]?.value.simpleText == players)
            #expect(game.root["C"]?.value.text == comment)
            #expect(game.encoding == .windowsCP1252)
            #expect(collection.warnings.map(\.kind)
                == (declaration.isEmpty ? [] : [.encodingFallback(declared: "UTF-8", used: "Windows-1252")]))
        }
    }

    @Test(arguments: ["Émile", "Ängelholm", "Æsir", "Çelik", "Élodie Martin", "Ü", "½ point", "it´s", "ÀÁ"])
    func shortWesternTextIsNotMistakenForAnAsianCharset(text: String) throws {
        // macOS's detection alone reads these as Big5, GBK, or Shift_JIS half-width katakana.
        let game = try firstGame(bytes: ascii("(;PB[") + encoded(text, .windowsCP1252) + ascii("])"))
        #expect(game.root["PB"]?.value.simpleText == text)
        #expect(game.encoding == .windowsCP1252)
    }

    @Test func eachGameInACollectionHasItsOwnCharset() throws {
        let bytes = ascii("(;CA[UTF-8]PB[Jos") + [0xC3, 0xA9] + ascii("])")
            + ascii("(;CA[ISO-8859-1]PB[Jos") + [0xE9] + ascii("])")
        let collection = parse(bytes: bytes)
        #expect(collection.games.map { $0.root["PB"]?.value.simpleText } == ["Jos\u{E9}", "Jos\u{E9}"])
        #expect(collection.warnings.isEmpty)
    }
}

/// The bytes of a string in an encoding.
private func encoded(_ text: String, _ encoding: String.Encoding) -> [UInt8] {
    Array(text.data(using: encoding)!)
}

/// The bytes of a string in a Core Foundation charset.
private func encoded(_ text: String, _ charset: CFStringEncodings) -> [UInt8] {
    encoded(text, String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(charset.rawValue))))
}
