import CoreGraphics

/// Where the board and the details go on one screen, for one game (see `docs/screensaver.md`,
/// section 5).
///
/// For a screen of W by H points, with a margin m of 4% of the shorter side:
/// 1. A preview, any view whose shorter side is under 400 points, gets a board of 90% of its
///    shorter side, centered, and no details.
/// 2. Otherwise the details go beside the board on the screen's long axis. On a landscape screen,
///    the board's side is s = min(0.86 H, W − w − 3m), where w is the details' width, so a band
///    for the details always fits; the board is centered vertically.
/// 3. A side, left or right, is chosen at random, then the board's position at random within the
///    range that leaves that band at least w + 2m wide and keeps the board m from the edges.
/// 4. The details go at a random place in that band, at least m from every edge and from the
///    board.
/// 5. A portrait screen is the same turned: the details go above or below the board, with their
///    height in place of their width.
/// 6. If s comes out under 60% of the shorter side, or the details are too tall for the band,
///    the game has no details, and the board is centered.
///
/// So the board moves a little from game to game, which also spares the screen a fixed image.
/// Rects are in the screen's own points, with the origin at a corner; which corner doesn't
/// matter, since every choice is symmetrical.
struct SaverLayout: Sendable, Equatable {
    /// Where the details go, relative to the board.
    enum Side: Sendable, Equatable, CaseIterable {
        case left, right, below, above
    }

    /// The screen's size, in points.
    let screen: CGSize

    /// The board's rect, a square.
    let board: CGRect

    /// The details' rect, or `nil` if this game has none.
    let details: CGRect?

    /// The side of the board the details are on.
    let side: Side?

    /// Whether the screen is a preview (see ``isPreview(_:)``).
    let isPreview: Bool

    /// Whether the details were left out because the screen's shape leaves no room for them.
    let leftOutDetails: Bool

    /// The space kept between the details, the board, and the edges.
    var margin: CGFloat { Self.margin(for: screen) }

    /// Whether a view of a size is a preview, such as the one in System Settings: its shorter
    /// side is under 400 points. Decided by size alone, because `isPreview` is reported wrong
    /// on macOS 26.
    static func isPreview(_ size: CGSize) -> Bool {
        min(size.width, size.height) < Look.screensaverPreviewMaximumSide
    }

    /// The margin for a screen: 4% of its shorter side.
    static func margin(for screen: CGSize) -> CGFloat {
        min(screen.width, screen.height) * Look.screensaverMarginFraction
    }

    /// The widest the details may be on a screen.
    static func maximumDetailsWidth(for screen: CGSize) -> CGFloat {
        screen.width * (screen.width >= screen.height
            ? Look.screensaverDetailsWidthFraction : Look.screensaverPortraitDetailsWidthFraction)
    }

    /// The layout of a game on a screen, or `nil` if the screen has no area.
    ///
    /// - Parameters:
    ///   - details: The details' size, or `nil` if the game has none.
    ///   - generator: Chooses the side and the positions.
    init?(screen: CGSize, details size: CGSize?, using generator: inout some RandomNumberGenerator) {
        guard screen.width.isFinite, screen.height.isFinite, screen.width > 0, screen.height > 0 else { return nil }
        self.screen = screen
        let shorter = min(screen.width, screen.height)
        isPreview = Self.isPreview(screen)
        if isPreview {
            board = Self.centered(side: shorter * Look.screensaverPreviewBoardFraction, in: screen)
            details = nil
            side = nil
            leftOutDetails = false
            return
        }

        // Work along the long axis (x on a landscape screen) and across it (y).
        let landscape = screen.width >= screen.height
        let long = landscape ? screen.width : screen.height
        let across = landscape ? screen.height : screen.width
        let m = Self.margin(for: screen)
        let fullBoard = across * Look.screensaverBoardFraction
        guard let size, size.width > 0, size.height > 0 else {
            board = Self.centered(side: fullBoard, in: screen)
            details = nil
            side = nil
            leftOutDetails = false
            return
        }
        let alongDetails = landscape ? size.width : size.height
        let acrossDetails = landscape ? size.height : size.width
        let s = min(fullBoard, long - alongDetails - 3 * m)
        guard s >= shorter * Look.screensaverMinimumBoardFraction, acrossDetails <= across - 2 * m else {
            board = Self.centered(side: fullBoard, in: screen)
            details = nil
            side = nil
            leftOutDetails = true
            return
        }

        // Both sides can hold the details, since s leaves room for them.
        let after = Bool.random(using: &generator)
        let boardStart: CGFloat
        let detailsStart: CGFloat
        if after {
            // Board first, then the band: the board from m to where the band still fits.
            boardStart = Self.random(from: m, to: long - s - alongDetails - 2 * m, using: &generator)
            detailsStart = Self.random(from: boardStart + s + m, to: long - m - alongDetails, using: &generator)
        } else {
            boardStart = Self.random(from: alongDetails + 2 * m, to: long - s - m, using: &generator)
            detailsStart = Self.random(from: m, to: boardStart - m - alongDetails, using: &generator)
        }
        let detailsAcross = Self.random(from: m, to: across - m - acrossDetails, using: &generator)
        let boardAcross = (across - s) / 2
        if landscape {
            board = CGRect(x: boardStart, y: boardAcross, width: s, height: s)
            details = CGRect(x: detailsStart, y: detailsAcross, width: size.width, height: size.height)
            side = after ? .right : .left
        } else {
            board = CGRect(x: boardAcross, y: boardStart, width: s, height: s)
            details = CGRect(x: detailsAcross, y: detailsStart, width: size.width, height: size.height)
            side = after ? .above : .below
        }
        leftOutDetails = false
    }

    private static func centered(side: CGFloat, in screen: CGSize) -> CGRect {
        CGRect(x: (screen.width - side) / 2, y: (screen.height - side) / 2, width: side, height: side)
    }

    /// A random value from `lower` to `upper`, or `lower` if rounding has put `upper` below it.
    private static func random(from lower: CGFloat, to upper: CGFloat, using generator: inout some RandomNumberGenerator) -> CGFloat {
        upper > lower ? CGFloat.random(in: lower ... upper, using: &generator) : lower
    }
}
