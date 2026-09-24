/// A point on the board, in SGF coordinates.
///
/// Columns count from the left and rows from the top, both starting at 1, as in SGF. In SGF text
/// a point is two letters, column first: `a`-`z` are 1-26 and `A`-`Z` are 27-52, so `aa` is the
/// top-left corner and `pd` is column 16, row 4.
public struct SGFPoint: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// The column, counting from 1 at the left edge.
    public let column: Int

    /// The row, counting from 1 at the top edge.
    public let row: Int

    /// Creates a point from its column and row, both counting from 1.
    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    /// Creates a point from its two SGF letters, such as `"pd"`.
    ///
    /// Surrounding whitespace is ignored. Returns `nil` for anything other than two letters.
    init?(sgf: String) {
        var scalars = sgf.unicodeScalars[...]
        while let first = scalars.first, first.properties.isWhitespace { scalars.removeFirst() }
        while let last = scalars.last, last.properties.isWhitespace { scalars.removeLast() }
        guard scalars.count == 2,
              let column = Self.coordinate(of: scalars.first!),
              let row = Self.coordinate(of: scalars.last!)
        else { return nil }
        self.init(column: column, row: row)
    }

    /// The point's two SGF letters, such as `"pd"`. A coordinate outside 1-52 is written as `?`.
    var sgf: String {
        String(Self.letter(for: column)) + String(Self.letter(for: row))
    }

    public var description: String { sgf }

    /// Orders points column by column, then row by row, the order 1.x used for positions.
    public static func < (lhs: SGFPoint, rhs: SGFPoint) -> Bool {
        (lhs.column, lhs.row) < (rhs.column, rhs.row)
    }

    /// The coordinate (1-52) of an SGF letter.
    static func coordinate(of scalar: Unicode.Scalar) -> Int? {
        switch scalar.value {
        case 0x61 ... 0x7A: Int(scalar.value) - 0x61 + 1   // a-z
        case 0x41 ... 0x5A: Int(scalar.value) - 0x41 + 27  // A-Z
        default: nil
        }
    }

    /// The SGF letter for a coordinate (1-52).
    static func letter(for coordinate: Int) -> Character {
        switch coordinate {
        case 1 ... 26: Character(Unicode.Scalar(UInt8(0x61 + coordinate - 1)))
        case 27 ... 52: Character(Unicode.Scalar(UInt8(0x41 + coordinate - 27)))
        default: "?"
        }
    }
}
