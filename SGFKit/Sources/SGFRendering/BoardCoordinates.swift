import SGFKit

/// Board coordinates as GoBooks and most Go books write them: a letter for the column, counting
/// from the left and skipping I, and a number for the row, counting from 1 at the bottom. The
/// top-right corner of a 19x19 board is T19, and the SGF point `pd` is Q16.
public enum BoardCoordinates {
    /// The 25 column letters, A to Z without I.
    private static let letters = Array("ABCDEFGHJKLMNOPQRSTUVWXYZ")

    /// The label of a column, counting from 1 at the left.
    ///
    /// Columns 1-25 are A to Z without I. Past 25, the labels continue the way spreadsheet
    /// columns do, with the same 25 letters: AA to AZ for columns 26-50, then BA and BB for 51
    /// and 52. Returns an empty string for a column below 1.
    public static func columnLabel(_ column: Int) -> String {
        var remaining = column
        var label = ""
        while remaining > 0 {
            remaining -= 1
            label.insert(letters[remaining % letters.count], at: label.startIndex)
            remaining /= letters.count
        }
        return label
    }

    /// The label of a row: its number counting from 1 at the bottom of a board with `rows` rows.
    /// The `row` is counted from 1 at the top, as in SGF.
    public static func rowLabel(_ row: Int, rows: Int) -> String {
        String(rows - row + 1)
    }

    /// The name of a point, such as `"Q16"` for the SGF point `pd` on a 19x19 board.
    public static func name(of point: SGFPoint, on size: BoardSize) -> String {
        columnLabel(point.column) + rowLabel(point.row, rows: size.rows)
    }
}
