import CoreGraphics
import SGFRendering

/// The look of thumbnails and previews, in one place so that it's easy to change.
enum Look {
    // MARK: Which position

    /// The number of opening moves shown on boards whose shorter side is 19 lines or more.
    static let openingMovesOnLargeBoards = 50

    /// The number of opening moves shown on boards whose shorter side is 13 to 18 lines.
    static let openingMovesOnMediumBoards = 30

    /// The number of opening moves shown on smaller boards.
    static let openingMovesOnSmallBoards = 20

    // MARK: Thumbnails

    /// The board style of thumbnails.
    static let thumbnailStyle = BoardStyle.shaded

    /// Extra board around the grid of a thumbnail, in cells. At 0, edge stones reach the edge of
    /// the board, as on a real board.
    static let thumbnailMargin: CGFloat = 0

    /// Whether a thumbnail marks the last move shown.
    static let thumbnailMarksLastMove = false

    /// Whether a file with several games gets the stacked-boards backdrop.
    static let thumbnailShowsCollectionBackdrop = true

    // MARK: Previews

    /// The board style of previews.
    static let previewStyle = BoardStyle.shaded

    /// Extra board around the grid of a preview, in cells.
    static let previewMargin: CGFloat = 0

    /// The sides of the preview's board that carry coordinates.
    static let previewCoordinateSides = CoordinateSides.leftAndBottom

    /// Whether the preview marks the last move shown.
    static let previewMarksLastMove = true

    /// The size the preview asks Quick Look for, in points.
    static let previewSize = CGSize(width: 900, height: 580)

    /// The width of the game information beside the board, in points.
    static let previewInfoWidth: CGFloat = 300

    /// The smallest board the preview puts beside the game information, in points. Where the
    /// space is narrower than this plus the information, as in Finder's Get Info and column view,
    /// the board goes above the information instead.
    static let previewMinimumBoardSide: CGFloat = 260
}
