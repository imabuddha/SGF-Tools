import Foundation

/// Reads SGF data into games.
///
/// The parser is tolerant: it never fails and never crashes on bad input. It makes the best of
/// malformed or truncated files and reports what it had to work around as ``SGFWarning``s.
///
/// - Text before, between, and after game trees is skipped, including a byte-order mark or the
///   literal `&#65279;` that some web downloads leave at the start. A game tree starts at a `(`
///   followed, after optional whitespace, by `;`, or by a property whose identifier is all
///   uppercase letters, which makes a root node whose `;` is missing.
/// - Each game's text is decoded with the charset its CA property names. Without CA, UTF-8 is
///   tried first, with any character that a soft line break splits joined again. When the text
///   should be UTF-8 but isn't, its charset is detected among the usual Chinese, Korean,
///   Japanese, and Western ones, with Windows-1252 (which covers Latin-1) as the last resort;
///   Western text in UTF-8 with a few stray bytes stays UTF-8, with those bytes in Windows-1252.
///   When the text isn't valid in another declared charset, the parser falls back to
///   Windows-1252 or, for a file labeled Latin-1 that is really UTF-8, to UTF-8.
/// - UTF-16 files (with or without a byte-order mark) are converted to UTF-8 first.
/// - Lowercase letters in property identifiers are ignored, as FF[1]-FF[3] allowed, so
///   `AddBlack` reads as `AB`.
/// - Game trees and variations are parsed without recursion, so nesting depth doesn't matter.
public enum SGFParser {
    /// Options for parsing.
    public struct Options: Sendable, Hashable {
        /// Stop after the first game tree, leaving the rest of the data unread. For thumbnails,
        /// and for previews of large files. ``SGFCollection/isCollection`` still tells whether
        /// the file holds more than one game.
        public var stopAfterFirstGame: Bool

        /// Creates parsing options.
        public init(stopAfterFirstGame: Bool = false) {
            self.stopAfterFirstGame = stopAfterFirstGame
        }
    }

    /// Parses SGF data. This never fails: data with no game tree gives an empty collection.
    public static func parse(_ data: Data, options: Options = Options()) -> SGFCollection {
        if let utf8 = convertedFromUTF16(data) {
            return utf8.withUnsafeBufferPointer { bytes in
                var parser = ByteParser(bytes: bytes, options: options, isConvertedFromUTF16: true)
                return parser.parseCollection()
            }
        }
        return data.withUnsafeBytes { raw in
            raw.withMemoryRebound(to: UInt8.self) { bytes in
                var parser = ByteParser(bytes: bytes, options: options, isConvertedFromUTF16: false)
                return parser.parseCollection()
            }
        }
    }

    /// The data converted to UTF-8 if it looks like UTF-16: a UTF-16 byte-order mark, or an
    /// ASCII character next to a zero byte at the start (SGF text never contains zero bytes).
    private static func convertedFromUTF16(_ data: Data) -> [UInt8]? {
        guard data.count >= 2 else { return nil }
        let first = data[data.startIndex]
        let second = data[data.startIndex + 1]
        let encoding: String.Encoding
        var body = data
        switch (first, second) {
        case (0xFF, 0xFE):
            encoding = .utf16LittleEndian
            body = data.dropFirst(2)
        case (0xFE, 0xFF):
            encoding = .utf16BigEndian
            body = data.dropFirst(2)
        case (1 ... 0x7F, 0):
            encoding = .utf16LittleEndian
        case (0, 1 ... 0x7F):
            encoding = .utf16BigEndian
        default:
            return nil
        }
        guard let text = String(data: body, encoding: encoding) else { return nil }
        return Array(text.utf8)
    }
}

// MARK: - Byte parser

/// A property as parsed, before its values are decoded: byte ranges into the data.
private struct RawProperty {
    var identifier: String
    var values: [Range<Int>]
}

/// A node as parsed, before its values are decoded.
private struct RawNode {
    var parentID: Int?
    var childIDs: [Int] = []
    var properties: [RawProperty] = []
}

/// The result of parsing one game tree's structure.
private struct RawTree {
    var nodes: [RawNode] = []
    var warnings: [SGFWarning] = []
    /// The offset just past the tree (or of where parsing stopped).
    var end: Int
}

private enum ASCII {
    static let openParenthesis: UInt8 = 0x28
    static let closeParenthesis: UInt8 = 0x29
    static let semicolon: UInt8 = 0x3B
    static let openBracket: UInt8 = 0x5B
    static let closeBracket: UInt8 = 0x5D
    static let backslash: UInt8 = 0x5C

    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (0x09 ... 0x0D).contains(byte)
    }

    static func isUppercase(_ byte: UInt8) -> Bool { (0x41 ... 0x5A).contains(byte) }

    static func isLetter(_ byte: UInt8) -> Bool { isUppercase(byte) || (0x61 ... 0x7A).contains(byte) }
}

private struct ByteParser {
    let bytes: UnsafeBufferPointer<UInt8>
    let options: SGFParser.Options
    let isConvertedFromUTF16: Bool
    var warnings: [SGFWarning] = []

    init(bytes: UnsafeBufferPointer<UInt8>, options: SGFParser.Options, isConvertedFromUTF16: Bool) {
        self.bytes = bytes
        self.options = options
        self.isConvertedFromUTF16 = isConvertedFromUTF16
    }

    mutating func parseCollection() -> SGFCollection {
        var games: [SGFGame] = []
        var position = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        while let start = gameTreeStart(from: position) {
            reportSkippedText(in: position ..< start)
            let (game, end) = parseGame(at: start)
            games.append(game)
            position = end
            if options.stopAfterFirstGame {
                return SGFCollection(games: games, warnings: warnings,
                                     moreGamesFollow: gameTreeStart(from: position) != nil)
            }
        }
        reportSkippedText(in: position ..< bytes.count)
        return SGFCollection(games: games, warnings: warnings)
    }

    /// The offset of the next `(` that is followed, after optional whitespace, by `;` or by the
    /// first property of a root node whose `;` is missing.
    private func gameTreeStart(from offset: Int) -> Int? {
        var index = offset
        while index < bytes.count {
            if bytes[index] == ASCII.openParenthesis {
                var next = index + 1
                while next < bytes.count, ASCII.isWhitespace(bytes[next]) { next += 1 }
                if next < bytes.count, bytes[next] == ASCII.semicolon || startsRootProperty(at: next) {
                    return index
                }
            }
            index += 1
        }
        return nil
    }

    /// Whether a property that can start a root node with no `;` is at `offset`: an identifier of
    /// uppercase letters, as FF[4] has them, followed, after optional whitespace, by `[`. Text in
    /// parentheses, such as "(Diagram 2)" or "(see diagram[1])", doesn't qualify.
    private func startsRootProperty(at offset: Int) -> Bool {
        var index = offset
        while index < bytes.count, ASCII.isUppercase(bytes[index]) { index += 1 }
        guard index > offset else { return false }
        while index < bytes.count, ASCII.isWhitespace(bytes[index]) { index += 1 }
        return index < bytes.count && bytes[index] == ASCII.openBracket
    }

    private mutating func reportSkippedText(in range: Range<Int>) {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, ASCII.isWhitespace(bytes[lower]) { lower += 1 }
        while upper > lower, ASCII.isWhitespace(bytes[upper - 1]) { upper -= 1 }
        if lower < upper {
            warnings.append(SGFWarning(.skippedText(byteCount: upper - lower), offset: lower))
        }
    }

    // MARK: Games

    /// Parses the game tree at `start`, returning the game and the offset just past it.
    private mutating func parseGame(at start: Int) -> (SGFGame, Int) {
        // Read the root node first to learn the charset, which decides how multibyte text is
        // scanned, then parse the whole tree with it.
        var charset = Charset.utf8
        if !isConvertedFromUTF16 {
            let root = parseTree(at: start, leadBytes: nil, rootOnly: true)
            charset = Charset(declared: declaredCharset(root: root, start: start))
        }
        var tree = parseTree(at: start, leadBytes: charset.leadBytes, rootOnly: false)
        var decoded = decodeValues(of: tree, charset: charset)
        if decoded == nil {
            // Not valid UTF-8: detect the charset, and parse again if its trail bytes can look
            // like `\` or `]`.
            charset = Charset(detected: CharsetDetection.detect(nonASCIISample(of: tree)), replacing: charset)
            if charset.leadBytes != nil {
                tree = parseTree(at: start, leadBytes: charset.leadBytes, rootOnly: false)
            }
            decoded = decodeValues(of: tree, charset: charset)
        }
        guard let decoded else { preconditionFailure("Only UTF-8 decoding can fail.") }

        warnings += tree.warnings
        if charset.isUnknown, let name = charset.declaredName {
            warnings.append(SGFWarning(.unknownCharset(name), offset: charsetOffset(in: tree) ?? start))
        }
        if let fallback = decoded.fallback {
            warnings.append(SGFWarning(fallback, offset: start))
        }
        let nodes = makeNodes(of: tree, values: decoded.strings)
        let game = SGFGame(nodes: nodes, encoding: decoded.encoding)
        if let size = nodes[0]["SZ"], game.declaredBoardSize == nil {
            let offset = tree.nodes[0].properties.first { $0.identifier == "SZ" }?.values.first?.lowerBound
            warnings.append(SGFWarning(.invalidBoardSize(size.value.simpleText.trimmingCharacters(in: .whitespaces)),
                                       offset: offset ?? start))
        }
        return (game, tree.end)
    }

    /// The CA value of a game's root node, as written. If the parsed root has none, the root's
    /// bytes are searched for `CA[`, because in a multibyte charset a value before CA can end in
    /// a byte that looks like a backslash and hide the rest of the node from a byte-wise parse.
    private func declaredCharset(root: RawTree, start: Int) -> String? {
        if let range = root.nodes.first?.properties.first(where: { $0.identifier == "CA" })?.values.first {
            return charsetName(in: range)
        }
        let pattern: [UInt8] = [0x43, 0x41, ASCII.openBracket]  // "CA["
        var index = start
        while index + pattern.count <= root.end {
            if bytes[index ..< index + pattern.count].elementsEqual(pattern),
               index == 0 || !ASCII.isLetter(bytes[index - 1]) {
                let valueStart = index + pattern.count
                var valueEnd = valueStart
                while valueEnd < bytes.count, bytes[valueEnd] != ASCII.closeBracket, valueEnd - valueStart < 64 {
                    valueEnd += 1
                }
                return charsetName(in: valueStart ..< valueEnd)
            }
            index += 1
        }
        return nil
    }

    private func charsetName(in range: Range<Int>) -> String? {
        let name = SGFValue(raw: TextDecoding.windows1252(bytes[range])).simpleText
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func charsetOffset(in tree: RawTree) -> Int? {
        tree.nodes.first?.properties.first { $0.identifier == "CA" }?.values.first?.lowerBound
    }

    // MARK: Structure

    /// Parses the structure of the game tree whose `(` is at `start`.
    ///
    /// - Parameters:
    ///   - leadBytes: The lead bytes of the charset's two-byte characters, if their second byte
    ///     can look like `\` or `]`.
    ///   - rootOnly: Stop when the root node ends.
    private func parseTree(at start: Int, leadBytes: [Bool]?, rootOnly: Bool) -> RawTree {
        var tree = RawTree(end: start)
        var openParents: [Int?] = []  // the current node when each open "(" was read
        var current: Int?
        var lastUnexpected = -2
        var index = start
        var closed = false

        parsing: while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case ASCII.openParenthesis, ASCII.closeParenthesis, ASCII.semicolon:
                if rootOnly, !tree.nodes.isEmpty { break parsing }
                index += 1
                if byte == ASCII.openParenthesis {
                    openParents.append(current)
                } else if byte == ASCII.closeParenthesis {
                    current = openParents.popLast() ?? nil
                    if openParents.isEmpty {
                        closed = true
                        break parsing
                    }
                } else {
                    let id = tree.nodes.count
                    tree.nodes.append(RawNode(parentID: current))
                    if let current { tree.nodes[current].childIDs.append(id) }
                    current = id
                }
            case _ where ASCII.isLetter(byte):
                if current == nil, tree.nodes.isEmpty {
                    // Properties right after the tree's "(": the root node, whose ";" is missing.
                    tree.nodes.append(RawNode(parentID: nil))
                    current = 0
                    tree.warnings.append(SGFWarning(.missingSemicolon, offset: index))
                }
                index = parseProperty(at: index, into: &tree, node: current, leadBytes: leadBytes)
            case _ where ASCII.isWhitespace(byte):
                index += 1
            default:
                if index != lastUnexpected + 1 {
                    let character = Character(Unicode.Scalar(byte))
                    tree.warnings.append(SGFWarning(.unexpectedCharacter(character), offset: index))
                }
                lastUnexpected = index
                index += 1
            }
        }
        if !closed, !rootOnly {
            tree.warnings.append(SGFWarning(.missingCloseParenthesis(count: openParents.count), offset: index))
        }
        tree.end = index
        return tree
    }

    /// Parses a property identifier and its values, adding them to `node`. Returns the offset
    /// just past the property.
    private func parseProperty(at start: Int, into tree: inout RawTree, node: Int?, leadBytes: [Bool]?) -> Int {
        var index = start
        var identifier = ""
        while index < bytes.count, ASCII.isLetter(bytes[index]) {
            if ASCII.isUppercase(bytes[index]) { identifier.unicodeScalars.append(Unicode.Scalar(bytes[index])) }
            index += 1
        }
        let written = String(decoding: bytes[start ..< index], as: UTF8.self)
        let name = identifier.isEmpty ? written : identifier

        var values: [Range<Int>] = []
        while true {
            var next = index
            while next < bytes.count, ASCII.isWhitespace(bytes[next]) { next += 1 }
            guard next < bytes.count, bytes[next] == ASCII.openBracket else { break }
            let valueStart = next + 1
            var valueEnd = valueStart
            var terminated = false
            while valueEnd < bytes.count {
                let byte = bytes[valueEnd]
                if byte == ASCII.closeBracket {
                    terminated = true
                    break
                }
                if byte == ASCII.backslash || leadBytes?[Int(byte)] == true {
                    valueEnd += 2
                } else {
                    valueEnd += 1
                }
            }
            valueEnd = min(valueEnd, bytes.count)
            values.append(valueStart ..< valueEnd)
            if terminated {
                index = valueEnd + 1
            } else {
                tree.warnings.append(SGFWarning(.unterminatedValue(property: name), offset: valueStart))
                index = valueEnd
            }
        }

        if identifier.isEmpty {
            tree.warnings.append(SGFWarning(.invalidPropertyIdentifier(written), offset: start))
        } else if values.isEmpty {
            tree.warnings.append(SGFWarning(.missingValue(property: identifier), offset: start))
        } else if let node {
            if let existing = tree.nodes[node].properties.firstIndex(where: { $0.identifier == identifier }) {
                tree.nodes[node].properties[existing].values += values
                tree.warnings.append(SGFWarning(.duplicateProperty(identifier), offset: start))
            } else {
                tree.nodes[node].properties.append(RawProperty(identifier: identifier, values: values))
            }
        }
        return index
    }

    // MARK: Decoding

    /// The decoded values of a tree, in the order of its nodes, properties, and values.
    private struct DecodedValues {
        var strings: [String]
        var encoding: String.Encoding
        /// Why the text was decoded in a charset other than the declared one, if it was.
        var fallback: SGFWarning.Kind?
    }

    /// Decodes the values of a parsed tree. Returns `nil` only for the UTF-8 charset (no CA, or
    /// CA naming UTF-8 or an unknown charset) when the text isn't valid UTF-8; the caller then
    /// detects the charset.
    private func decodeValues(of tree: RawTree, charset: Charset) -> DecodedValues? {
        let bytes = bytes
        let ranges = tree.nodes.flatMap { $0.properties.flatMap(\.values) }

        func decodeAll(_ decoder: (Slice<UnsafeBufferPointer<UInt8>>) -> String?) -> [String]? {
            var result: [String] = []
            result.reserveCapacity(ranges.count)
            for range in ranges {
                guard let string = decoder(bytes[range]) else { return nil }
                result.append(string)
            }
            return result
        }

        func windows1252() -> [String] { ranges.map { TextDecoding.windows1252(bytes[$0]) } }

        /// Decodes each value in `encoding`, or in Windows-1252 if it isn't valid there.
        func decodeEach(as encoding: String.Encoding) -> (strings: [String], fellBack: Bool) {
            var fellBack = false
            let strings = ranges.map { range in
                if let string = TextDecoding.decode(bytes[range], as: encoding) { return string }
                fellBack = true
                return TextDecoding.windows1252(bytes[range])
            }
            return (strings, fellBack)
        }

        /// A fallback warning for a game that declared a known charset.
        func fallback(to used: String) -> SGFWarning.Kind? {
            guard let declared = charset.declaredName, !charset.isUnknown else { return nil }
            return .encodingFallback(declared: declared, used: used)
        }

        switch charset.kind {
        case _ where isConvertedFromUTF16:
            return DecodedValues(strings: decodeAll(TextDecoding.utf8) ?? windows1252(), encoding: .utf8)
        case .utf8:
            return decodeAll(TextDecoding.utf8).map { DecodedValues(strings: $0, encoding: .utf8) }
        case .detected(let detected):
            // Without CA, FF[4] makes Latin-1 the default, so reading Windows-1252 or any other
            // detected charset isn't worth a warning. Declaring UTF-8 wrongly is.
            if detected == .windowsCP1252 {
                return DecodedValues(strings: windows1252(), encoding: .windowsCP1252,
                                     fallback: fallback(to: CharsetDetection.name(of: .windowsCP1252)))
            }
            if detected == .utf8 {
                // Western text in UTF-8 with a few stray bytes, which are read as Windows-1252.
                return DecodedValues(strings: ranges.map { TextDecoding.utf8WithStrayBytes(bytes[$0]) },
                                     encoding: .utf8, fallback: fallback(to: "UTF-8 and Windows-1252"))
            }
            let (strings, _) = decodeEach(as: detected)
            return DecodedValues(strings: strings, encoding: detected,
                                 fallback: fallback(to: CharsetDetection.name(of: detected)))
        case .western:
            let hasNonASCII = ranges.contains { range in bytes[range].contains { $0 >= 0x80 } }
            if hasNonASCII, let utf8 = decodeAll(TextDecoding.utf8) {
                return DecodedValues(strings: utf8, encoding: .utf8, fallback: fallback(to: "UTF-8"))
            }
            return DecodedValues(strings: windows1252(), encoding: .windowsCP1252)
        case .other(let declared):
            let (strings, fellBack) = decodeEach(as: declared)
            return DecodedValues(strings: strings, encoding: declared,
                                 fallback: fellBack ? fallback(to: "Windows-1252") : nil)
        }
    }

    /// The values of a tree that contain non-ASCII bytes, separated by line breaks, for charset
    /// detection.
    private func nonASCIISample(of tree: RawTree) -> [UInt8] {
        var sample: [UInt8] = []
        for node in tree.nodes {
            for property in node.properties {
                for range in property.values where bytes[range].contains(where: { $0 >= 0x80 }) {
                    if !sample.isEmpty { sample.append(0x0A) }
                    sample += bytes[range]
                    if sample.count >= CharsetDetection.maximumSampleSize { return sample }
                }
            }
        }
        return sample
    }

    /// Builds the nodes of a tree from its decoded values.
    private func makeNodes(of tree: RawTree, values: [String]) -> [SGFNode] {
        var nextString = values.makeIterator()
        return tree.nodes.enumerated().map { id, raw in
            SGFNode(
                id: id,
                parentID: raw.parentID,
                childIDs: raw.childIDs,
                properties: raw.properties.map { property in
                    SGFProperty(identifier: property.identifier,
                                values: property.values.map { _ in SGFValue(raw: nextString.next()!) })
                }
            )
        }
    }
}
