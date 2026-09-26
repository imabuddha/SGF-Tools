import CoreGraphics
import SGFRendering

/// The look of thumbnails, previews, and the screensaver, in one place so that it's easy to
/// change.
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

    // MARK: Screensaver

    // Each game plays the first moves of its main line (``Playlist/moveLimit``), on every board
    // size (see docs/screensaver.md, sections 4 and 5).

    /// The board style of the screensaver.
    static let screensaverStyle = BoardStyle.shaded

    /// Extra board around the grid of the screensaver's board, in cells.
    static let screensaverMargin: CGFloat = 0

    /// Whether the screensaver marks the last move.
    static let screensaverMarksLastMove = true

    /// How long the board takes to fade in, in seconds.
    static let screensaverFadeIn: Double = 2

    /// When the details start to fade in, in seconds after the board starts.
    static let screensaverDetailsDelay: Double = 0.75

    /// How long the details take to fade in, in seconds.
    static let screensaverDetailsFadeIn: Double = 1.5

    /// When the first move is played, in seconds after the board starts to fade in.
    static let screensaverFirstMove: Double = 3

    /// The first game after the screensaver starts comes in quicker than the rest, so that
    /// there's something to see almost at once: how long its board takes to fade in, in seconds.
    static let screensaverStartFadeIn: Double = 1

    /// When the first game's details start to fade in, in seconds after its board starts.
    static let screensaverStartDetailsDelay: Double = 0.3

    /// How long the first game's details take to fade in, in seconds.
    static let screensaverStartDetailsFadeIn: Double = 1

    /// When the first game's first move is played, in seconds after its board starts to fade in.
    static let screensaverStartFirstMove: Double = 2

    /// The time between moves, in seconds. With ``screensaverFinalHold``, it sets the pace: a
    /// 50-move game plays for about 25 s and holds its last position for 10 s.
    static let screensaverMoveInterval: Double = 0.5

    /// How long a new stone takes to appear, and captured stones to vanish, in seconds: less than
    /// ``screensaverMoveInterval``.
    static let screensaverMoveFade: Double = 0.3

    /// How long the last position stays before the board fades out, in seconds.
    static let screensaverFinalHold: Double = 10

    /// How long the board and details take to fade out, in seconds.
    static let screensaverFadeOut: Double = 2

    /// How long the screen stays black before the next game, in seconds.
    static let screensaverPause: Double = 1

    /// How long a screen stays black before its first game, in seconds.
    static let screensaverStartDelay: Double = 0.4

    /// The most that a screen's first game holds its last position longer than the others, in
    /// seconds. Each screen holds it a random time longer, so that screens that start together
    /// don't fade out and in together afterward.
    static let screensaverMaximumStagger: Double = 3

    /// A view whose shorter side is under this, in points, is a preview, such as the one in
    /// System Settings.
    static let screensaverPreviewMaximumSide: CGFloat = 400

    /// The board's side in a preview, as a fraction of its shorter side.
    static let screensaverPreviewBoardFraction: CGFloat = 0.9

    /// The board's largest side on a screen, as a fraction of its shorter side.
    static let screensaverBoardFraction: CGFloat = 0.86

    /// The smallest board that leaves room for the details, as a fraction of the shorter side.
    /// On a screen of a shape that leaves less, the game has no details.
    static let screensaverMinimumBoardFraction: CGFloat = 0.6

    /// The space kept between the details, the board, and the screen's edges, as a fraction of
    /// the screen's shorter side.
    static let screensaverMarginFraction: CGFloat = 0.04

    /// The widest the details may be, as a fraction of a landscape screen's width.
    static let screensaverDetailsWidthFraction: CGFloat = 0.3

    /// The widest the details may be, as a fraction of a portrait screen's width.
    static let screensaverPortraitDetailsWidthFraction: CGFloat = 0.9

    /// The size of the players' names, as a fraction of the screen's shorter side.
    static let screensaverPlayerFontFraction: CGFloat = 0.026

    /// The size of the other details, as a fraction of the screen's shorter side.
    static let screensaverDetailFontFraction: CGFloat = 0.019

    /// The opacity of the players' names, in white.
    static let screensaverPlayerOpacity: CGFloat = 0.95

    /// The opacity of the other details, in white.
    static let screensaverDetailOpacity: CGFloat = 0.7
}
