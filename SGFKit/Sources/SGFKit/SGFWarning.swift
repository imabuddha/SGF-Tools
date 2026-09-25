/// Something the parser tolerated: malformed input it worked around, or text it had to guess
/// the encoding of. A warning never means the file failed to parse.
public struct SGFWarning: Sendable, Hashable, CustomStringConvertible {
    /// What the parser found.
    public enum Kind: Sendable, Hashable {
        /// Text outside any game tree was skipped, such as a web page's leftovers before the
        /// first `(;`. The count excludes whitespace around the text.
        case skippedText(byteCount: Int)

        /// A character that doesn't belong between nodes and properties was ignored, such as a
        /// stray `]`. A run of such characters gives one warning.
        case unexpectedCharacter(Character)

        /// A property identifier with no uppercase letters was ignored, along with its values.
        case invalidPropertyIdentifier(String)

        /// A property identifier had no value after it and was ignored.
        case missingValue(property: String)

        /// The data ended inside a property value; the value keeps what was there.
        case unterminatedValue(property: String)

        /// A property appeared twice in one node; its values were merged into the first.
        case duplicateProperty(String)

        /// The data ended with this many game trees or variations still open.
        case missingCloseParenthesis(count: Int)

        /// A game tree's first properties came right after its `(`, with no `;` to start the
        /// root node, and were read as the root node.
        case missingSemicolon

        /// The charset named by CA is unknown, so the game was decoded as if it had no CA.
        case unknownCharset(String)

        /// The text wasn't valid in the declared charset, so the game was decoded in another one.
        case encodingFallback(declared: String, used: String)

        /// The SZ value isn't a valid board size, so the game uses 19x19.
        case invalidBoardSize(String)
    }

    /// What the parser found.
    public let kind: Kind

    /// The byte offset in the data where it was found. For UTF-16 data, which is converted to
    /// UTF-8 first, the offset is into the converted bytes.
    public let offset: Int

    /// Creates a warning.
    init(_ kind: Kind, offset: Int) {
        self.kind = kind
        self.offset = offset
    }

    public var description: String {
        let message = switch kind {
        case .skippedText(let count):
            "skipped \(count) bytes of text outside any game tree"
        case .unexpectedCharacter(let character):
            "ignored unexpected character \(character.debugDescription)"
        case .invalidPropertyIdentifier(let identifier):
            "ignored property \(identifier), which has no uppercase letters"
        case .missingValue(let property):
            "ignored property \(property), which has no value"
        case .unterminatedValue(let property):
            "the data ends inside a value of \(property)"
        case .duplicateProperty(let property):
            "merged a repeated \(property) property"
        case .missingCloseParenthesis(let count):
            "the data ends with \(count) unclosed parenthes\(count == 1 ? "is" : "es")"
        case .missingSemicolon:
            "read the properties after ( as the root node, which has no ;"
        case .unknownCharset(let name):
            "unknown charset \(name)"
        case .encodingFallback(let declared, let used):
            "the text isn't valid \(declared), so it was read as \(used)"
        case .invalidBoardSize(let value):
            "invalid board size \(value), so the board is 19x19"
        }
        return "byte \(offset): \(message)"
    }
}
