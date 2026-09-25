import Foundation

/// The size of a board: square, or rectangular as FF[4] allows, up to 52 in each direction.
public struct BoardSize: Sendable, Hashable, CustomStringConvertible {
    /// The largest number of columns or rows SGF can address (letters `a`-`z` and `A`-`Z`).
    static let maximum = 52

    /// The standard 19x19 board, also the SGF default when a game has no SZ property.
    public static let standard = BoardSize(uncheckedColumns: 19, rows: 19)

    /// The number of columns (the board's width).
    public let columns: Int

    /// The number of rows (the board's height).
    public let rows: Int

    /// Creates a board size, or returns `nil` unless both dimensions are in 1-52.
    public init?(columns: Int, rows: Int) {
        guard (1 ... Self.maximum).contains(columns), (1 ... Self.maximum).contains(rows) else { return nil }
        self.init(uncheckedColumns: columns, rows: rows)
    }

    /// Creates a square board size, or returns `nil` unless it is in 1-52.
    init?(_ size: Int) {
        self.init(columns: size, rows: size)
    }

    /// Creates a board size from the value of an SZ property: `"19"`, or `"19:13"` for a board
    /// 19 columns wide and 13 rows high. Surrounding whitespace is ignored.
    init?(sgf: String) {
        let parts = sgf.split(separator: ":", omittingEmptySubsequences: false)
        guard (1 ... 2).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            let digits = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit), digits.count <= 3,
                  let number = Int(digits)
            else { return nil }
            numbers.append(number)
        }
        self.init(columns: numbers[0], rows: numbers.last!)
    }

    private init(uncheckedColumns columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    /// Whether the board has as many columns as rows.
    var isSquare: Bool { columns == rows }

    /// The size as an SZ value: `"19"` for a square board, `"19:13"` otherwise.
    public var sgf: String { isSquare ? "\(columns)" : "\(columns):\(rows)" }

    /// The size for display, such as `"19x19"`.
    public var description: String { "\(columns)x\(rows)" }

    /// Whether a point lies on the board.
    func contains(_ point: SGFPoint) -> Bool {
        (1 ... columns).contains(point.column) && (1 ... rows).contains(point.row)
    }
}
