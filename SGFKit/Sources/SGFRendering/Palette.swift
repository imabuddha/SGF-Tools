import CoreGraphics

/// The colors of one style. All colors are sRGB.
///
/// Unchecked `Sendable`, because `CGGradient` isn't `Sendable`: a palette never changes once it is
/// made, so the built-in ones can be shared by every thread that draws.
struct Palette: @unchecked Sendable {
    /// The board's color where it is drawn without grain: the whole flat board, and the boards
    /// behind a collection.
    let board: CGColor
    /// A thin line around the wood, so a light board stands out from a light background.
    let boardEdge: CGColor
    /// The inner grid lines.
    let line: CGColor
    /// The inner grid lines of a compact board, drawn faint.
    let faintLine: CGColor
    /// The outer grid line.
    let frame: CGColor
    let starPoint: CGColor
    let label: CGColor

    let blackStone: CGColor
    let whiteStone: CGColor
    /// The outline of a white stone, if the style has one.
    let whiteOutline: CGColor?
    /// The unshaded white stone of a compact board, and its outline, if any.
    let compactWhiteStone: CGColor
    let compactWhiteOutline: CGColor?
    /// Black and white stones' shading, from the highlight to the rim, if the style has it.
    let blackShading: CGGradient?
    let whiteShading: CGGradient?
    /// A stone's shadow, from its center out to ``shadowReach`` times the stone's radius, if the
    /// style has one. It is solid to 0.8 times the radius, then fades out.
    let shadow: CGGradient?

    /// How far a shadow reaches, in stone radii.
    static let shadowReach: CGFloat = 1.12

    /// The last-move marker on a black stone and on a white one.
    let markerOnBlack: CGColor
    let markerOnWhite: CGColor

    static func of(_ look: BoardStyle.Look) -> Palette {
        switch look {
        case .shaded: shaded
        case .flat: flat
        }
    }

    static let shaded = Palette(
        board: WoodGrain.averageColor,
        boardEdge: rgb(0.36, 0.22, 0.08, 0.55),
        line: rgb(0.13, 0.08, 0.03, 0.66),
        faintLine: rgb(0.13, 0.08, 0.03, 0.26),
        frame: rgb(0.10, 0.06, 0.02, 0.90),
        starPoint: rgb(0.10, 0.06, 0.02, 0.92),
        label: rgb(0.24, 0.15, 0.05, 0.92),
        blackStone: rgb(0.07, 0.07, 0.08),
        whiteStone: rgb(0.83, 0.82, 0.79),
        whiteOutline: nil,
        compactWhiteStone: rgb(0.95, 0.95, 0.93),
        compactWhiteOutline: nil,
        blackShading: gradient([
            (0.00, rgb(0.46, 0.46, 0.48)),
            (0.30, rgb(0.23, 0.23, 0.24)),
            (1.00, rgb(0.07, 0.07, 0.08)),
        ]),
        whiteShading: gradient([
            (0.00, rgb(1.00, 1.00, 1.00)),
            (0.45, rgb(0.96, 0.96, 0.95)),
            (1.00, rgb(0.83, 0.82, 0.79)),
        ]),
        shadow: gradient([
            (0.00, rgb(0.10, 0.05, 0.00, 0.50)),
            (0.80 / shadowReach, rgb(0.10, 0.05, 0.00, 0.50)),
            (1.00, rgb(0.10, 0.05, 0.00, 0.00)),
        ]),
        markerOnBlack: rgb(0.96, 0.96, 0.96, 0.95),
        markerOnWhite: rgb(0.08, 0.08, 0.08, 0.90)
    )

    static let flat = Palette(
        board: rgb(0.965, 0.890, 0.720),
        boardEdge: rgb(0.40, 0.30, 0.15, 0.55),
        line: rgb(0, 0, 0),
        faintLine: rgb(0, 0, 0, 0.30),
        frame: rgb(0, 0, 0),
        starPoint: rgb(0, 0, 0),
        label: rgb(0, 0, 0, 0.90),
        blackStone: rgb(0, 0, 0),
        whiteStone: rgb(1, 1, 1),
        whiteOutline: rgb(0, 0, 0),
        compactWhiteStone: rgb(1, 1, 1),
        compactWhiteOutline: rgb(0, 0, 0, 0.55),
        blackShading: nil,
        whiteShading: nil,
        shadow: nil,
        markerOnBlack: rgb(1, 1, 1),
        markerOnWhite: rgb(0, 0, 0)
    )

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient? {
        CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops.map(\.1) as CFArray,
            locations: stops.map(\.0)
        )
    }
}
