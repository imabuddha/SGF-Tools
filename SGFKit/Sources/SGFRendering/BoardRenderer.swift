import CoreGraphics
import CoreText
import Foundation
import SGFKit

/// Draws Go board positions with Core Graphics, for thumbnails, previews, and the screensaver.
///
/// A renderer is a small value that holds the look; drawing takes the position:
///
///     let renderer = BoardRenderer(style: .shaded)
///     let image = renderer.makeImage(of: game.position(afterMainLineMoves: 50),
///                                    size: CGSize(width: 256, height: 256), scale: 2)
///
/// The board, with its coordinates if it has them, is fitted into the rect with square cells and
/// centered; anything else is left untouched, so an image of a rectangular board has transparent
/// sides. Grid lines are placed on whole device pixels, so they are crisp at any scale. Line
/// widths, stones, and labels all scale with the cell, so a board looks the same at any size,
/// only sharper.
///
/// Small boards are simplified. Below ``compactCellSize`` device pixels per cell, the inner
/// lines are drawn faint, stones fill their cells without shading, and star points and
/// coordinates are left out. Below 3 pixels per cell, the inner lines go too, and stones become
/// squares that fill their cells, so even a 16-pixel 19x19 thumbnail reads as a board of stones.
///
/// Drawing uses only Core Graphics and Core Text, so it works in app extensions and screensavers
/// alike. A renderer is a value and can be used from any thread.
public struct BoardRenderer: Sendable, Hashable {
    /// Device pixels per cell below which the board is drawn simplified: faint inner lines,
    /// stones that fill their cells, and no shading, star points, or coordinates.
    public static let compactCellSize: CGFloat = BoardLayout.compactCellSize

    /// The look of the board and stones.
    public var style: BoardStyle

    /// Whether to label the columns and rows (see ``BoardCoordinates``) on the sides in
    /// ``coordinateSides``. The labels go outside the board, in a band of their own, so they
    /// don't push the stones in. They are left out, and no room is made for them, when the board
    /// is too small for readable text.
    public var showsCoordinates: Bool

    /// The sides that carry coordinates when ``showsCoordinates`` is on: the left and bottom by
    /// default. ``CoordinateSides/all`` gives the four sides of GoBooks.
    public var coordinateSides: CoordinateSides

    /// The color of the coordinates. They are drawn outside the board, on whatever is behind it,
    /// so a caller drawing on a dark background should pass a light color. `nil` uses the style's
    /// own color, a dark brown or black for light backgrounds.
    public var coordinateColor: CGColor?

    /// Extra board around the grid, in cells, beyond the half cell that edge stones need.
    /// `0`, the default, lets the edge stones reach the edge of the board, as they do on a real
    /// board. Coordinates go outside the margin.
    public var margin: CGFloat

    /// Creates a renderer. The options are off by default.
    public init(
        style: BoardStyle = .shaded, showsCoordinates: Bool = false, coordinateSides: CoordinateSides = .leftAndBottom,
        coordinateColor: CGColor? = nil, margin: CGFloat = 0
    ) {
        self.style = style
        self.showsCoordinates = showsCoordinates
        self.coordinateSides = coordinateSides
        self.coordinateColor = coordinateColor
        self.margin = margin
    }

    /// Draws a position, fitted and centered in a rect.
    ///
    /// The grid is aligned to the context's device pixels. The board is drawn upright, with row 1
    /// at the top of the output, even if the context's user space is flipped. Drawing leaves the
    /// context's state as it was.
    ///
    /// - Parameters:
    ///   - board: The position.
    ///   - lastMove: A point to mark as the last move, with a ring on its stone. Nothing is
    ///     marked if the point is empty or off the board, or on a board too small to show it.
    ///   - context: Where to draw.
    ///   - rect: The area to fit the board and its coordinates into, in the context's user space.
    /// - Returns: The board's rect in user space, without the coordinates outside it. It is
    ///   `CGRect.null` if nothing was drawn because `rect` is empty.
    @discardableResult
    public func draw(_ board: Board, lastMove: SGFPoint? = nil, in context: CGContext, rect: CGRect) -> CGRect {
        Self.inPixelSpace(of: context, rect: rect) { pixelRect in
            guard let layout = BoardLayout(
                size: board.size, in: pixelRect, margin: margin, labelSides: showsCoordinates ? coordinateSides : []
            ) else { return nil }
            draw(board, lastMove: lastMove, layout: layout, in: context)
            return layout.boardRect
        }
    }

    /// Makes an image of a position.
    ///
    /// The image is `size` times `scale` pixels, so a 256x256 size at scale 2 makes a
    /// 512x512-pixel image. Where the board doesn't fill it, it is transparent. The image is
    /// in sRGB.
    ///
    /// - Returns: The image, or `nil` if the size is empty or too large (over 16,384 pixels a
    ///   side).
    public func makeImage(
        of board: Board, lastMove: SGFPoint? = nil, size: CGSize, scale: CGFloat = 1
    ) -> CGImage? {
        Self.makeImage(size: size, scale: scale) { context, rect in
            draw(board, lastMove: lastMove, in: context, rect: rect)
        }
    }

    // MARK: - Internal

    /// Runs `body` with the context's user space set to pixel space, and returns the rect that
    /// `body` returns, converted back to user space.
    ///
    /// Pixel space is the context's device space, with whole pixels at whole coordinates, turned
    /// if needed so that y points up on the output: toward the top of a bitmap's image, whatever
    /// the device's own orientation, and even if the caller's user space is flipped. If the
    /// current transform rotates or skews, drawing stays in user space, and whole units stand
    /// in for pixels.
    static func inPixelSpace(of context: CGContext, rect: CGRect, _ body: (CGRect) -> CGRect?) -> CGRect {
        let toPixels = pixelTransform(of: context)
        let pixelRect = rect.standardized.applying(toPixels).standardized

        context.saveGState()
        defer { context.restoreGState() }
        context.concatenate(toPixels.inverted())
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setAlpha(1)
        context.setBlendMode(.normal)
        guard let drawn = body(pixelRect) else { return .null }
        return drawn.applying(toPixels.inverted()).standardized
    }

    /// The transform from a context's user space to pixel space (see
    /// ``inPixelSpace(of:rect:_:)``), or the identity if the context rotates or skews.
    static func pixelTransform(of context: CGContext) -> CGAffineTransform {
        let toDevice = context.userSpaceToDeviceSpaceTransform
        guard toDevice.b == 0, toDevice.c == 0, toDevice.a != 0, toDevice.d != 0 else { return .identity }
        // A context's default user space has y pointing up on the output. Its device space may
        // not: a bitmap's device space has its origin at the top left. The CTM leaves out this
        // base transform, so compare the two.
        let base = context.ctm.inverted().concatenating(toDevice)
        return base.d < 0 ? toDevice.concatenating(CGAffineTransform(scaleX: 1, y: -1)) : toDevice
    }

    /// Makes a transparent sRGB bitmap of `size` times `scale` pixels, lets `drawing` draw into
    /// it (in points, y up), and returns the image.
    static func makeImage(size: CGSize, scale: CGFloat, drawing: (CGContext, CGRect) -> Void) -> CGImage? {
        guard size.width.isFinite, size.height.isFinite, scale.isFinite,
              size.width > 0, size.height > 0, scale > 0
        else { return nil }
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard (1 ... 16384).contains(width), (1 ... 16384).contains(height),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
        drawing(context, CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    // MARK: - Drawing, in pixel space

    private func draw(_ board: Board, lastMove: SGFPoint?, layout: BoardLayout, in context: CGContext) {
        let palette = Palette.of(style.look)
        context.saveGState()
        // Nothing, not even an edge stone's shadow, goes outside the board.
        context.clip(to: layout.boardRect)
        drawWood(layout: layout, palette: palette, in: context)
        drawGrid(layout: layout, palette: palette, in: context)
        if !layout.isCompact {
            drawStarPoints(of: board.size, layout: layout, palette: palette, in: context)
        }
        drawStones(of: board, layout: layout, palette: palette, in: context)
        if let lastMove {
            drawLastMoveMarker(at: lastMove, on: board, layout: layout, palette: palette, in: context)
        }
        context.restoreGState()
        if layout.showsLabels {
            drawLabels(layout: layout, color: coordinateColor ?? palette.label, in: context)
        }
    }

    private func drawWood(layout: BoardLayout, palette: Palette, in context: CGContext) {
        let rect = layout.boardRect
        if style.look == .shaded, let grain = WoodGrain.image {
            // Square, so the grain keeps its proportions; the clip to the board crops it.
            context.saveGState()
            context.interpolationQuality = .medium
            let side = max(rect.width, rect.height)
            context.draw(grain, in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
            context.restoreGState()
        } else {
            context.setFillColor(palette.board)
            context.fill(rect)
        }
        Self.fillEdge(of: rect, color: palette.boardEdge, in: context)
    }

    /// Fills a one-pixel line just inside a rect's edge.
    static func fillEdge(of rect: CGRect, color: CGColor, in context: CGContext) {
        guard rect.width > 2, rect.height > 2 else { return }
        let path = CGMutablePath()
        path.addRect(rect)
        path.addRect(rect.insetBy(dx: 1, dy: 1))
        context.addPath(path)
        context.setFillColor(color)
        context.fillPath(using: .evenOdd)
    }

    private func drawGrid(layout: BoardLayout, palette: Palette, in context: CGContext) {
        if !layout.isTiny {
            let lines = layout.innerLineRects
            if !lines.isEmpty {
                context.addRects(lines)
                context.setFillColor(layout.isCompact ? palette.faintLine : palette.line)
                context.fillPath()
            }
        }
        context.addRects(layout.frameRects)
        context.setFillColor(palette.frame)
        context.fillPath()
    }

    private func drawStarPoints(of size: BoardSize, layout: BoardLayout, palette: Palette, in context: CGContext) {
        let radius = max(layout.lineWidth * 1.25, layout.cell * 0.1)
        for point in size.starPoints {
            guard let center = layout.center(of: point) else { continue }
            context.addEllipse(in: Self.square(around: center, radius: radius))
        }
        context.setFillColor(palette.starPoint)
        context.fillPath()
    }

    /// Draws the coordinates in their bands outside the board.
    private func drawLabels(layout: BoardLayout, color: CGColor, in context: CGContext) {
        let fontSize = layout.cell * BoardLayout.labelFontRatio
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let capHeight = CTFontGetCapHeight(font)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        context.saveGState()
        context.setFillColor(color)
        context.textMatrix = .identity

        func draw(_ text: String, at centers: [CGPoint]) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            for center in centers {
                context.textPosition = CGPoint(x: center.x - width / 2, y: center.y - capHeight / 2)
                CTLineDraw(line, context)
            }
        }

        // From the outer lines, past the wood, to the middle of the band.
        let distance = layout.cell * (layout.woodBorder + BoardLayout.labelBand / 2)
        let topLeft = layout.center(column: 1, row: 1)
        let bottomRight = layout.center(column: layout.columns, row: layout.rows)
        let sides = layout.labelSides
        for column in 1 ... layout.columns {
            let x = layout.center(column: column, row: 1).x
            var centers: [CGPoint] = []
            if sides.contains(.top) { centers.append(CGPoint(x: x, y: topLeft.y + distance)) }
            if sides.contains(.bottom) { centers.append(CGPoint(x: x, y: bottomRight.y - distance)) }
            if !centers.isEmpty { draw(BoardCoordinates.columnLabel(column), at: centers) }
        }
        for row in 1 ... layout.rows {
            let y = layout.center(column: 1, row: row).y
            var centers: [CGPoint] = []
            if sides.contains(.left) { centers.append(CGPoint(x: topLeft.x - distance, y: y)) }
            if sides.contains(.right) { centers.append(CGPoint(x: bottomRight.x + distance, y: y)) }
            if !centers.isEmpty { draw(BoardCoordinates.rowLabel(row, rows: layout.rows), at: centers) }
        }
        context.restoreGState()
    }

    private func drawStones(of board: Board, layout: BoardLayout, palette: Palette, in context: CGContext) {
        let black = board.stones(of: .black).compactMap(layout.center(of:))
        let white = board.stones(of: .white).compactMap(layout.center(of:))
        guard !black.isEmpty || !white.isEmpty else { return }

        if layout.isTiny {
            // Squares that fill their cells, so the stones blend into whole pixels.
            let half = layout.cell / 2
            for (centers, color) in [(black, palette.blackStone), (white, palette.compactWhiteStone)] {
                guard !centers.isEmpty else { continue }
                context.addRects(centers.map { CGRect(x: $0.x - half, y: $0.y - half, width: 2 * half, height: 2 * half) })
                context.setFillColor(color)
                context.fillPath()
            }
        } else if layout.isCompact {
            let radius = layout.cell / 2
            fillDiscs(at: black, radius: radius, color: palette.blackStone, in: context)
            if let outline = palette.compactWhiteOutline {
                // A rim thinner than a pixel: a dark disc behind a slightly smaller white one.
                // A one-pixel stroke would cover most of a stone this small and turn it gray.
                fillDiscs(at: white, radius: radius, color: outline, in: context)
                fillDiscs(at: white, radius: radius - 0.5, color: palette.compactWhiteStone, in: context)
            } else {
                fillDiscs(at: white, radius: radius, color: palette.compactWhiteStone, in: context)
            }
        } else {
            let radius = layout.cell * 0.475
            if let shadow = palette.shadow {
                let offset = CGPoint(x: layout.cell * 0.07, y: -layout.cell * 0.09)
                let shadowRadius = radius * Palette.shadowReach
                for center in black + white {
                    let shadowCenter = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
                    Self.drawRadialGradient(
                        shadow, from: shadowCenter, radius: 0, to: shadowCenter, radius: shadowRadius, in: context
                    )
                }
            }
            drawStones(at: black, radius: radius, rim: palette.blackStone, shading: palette.blackShading, in: context)
            drawStones(at: white, radius: radius, rim: palette.whiteStone, shading: palette.whiteShading, in: context)
            if let outline = palette.whiteOutline {
                let width = layout.lineWidth
                strokeCircles(at: white, radius: radius - width / 2, width: width, color: outline, in: context)
            }
        }
    }

    /// Fills the stones with their rim color, then shades each one from a highlight toward the
    /// upper left. The shading stops just inside the rim, where it has reached the rim color, so
    /// the anti-aliased edge comes from the fill.
    private func drawStones(
        at centers: [CGPoint], radius: CGFloat, rim: CGColor, shading: CGGradient?, in context: CGContext
    ) {
        fillDiscs(at: centers, radius: radius, color: rim, in: context)
        guard let shading else { return }
        let shadingRadius = max(radius * 0.5, radius - 0.75)
        let highlightOffset = radius * 0.38
        for center in centers {
            let highlight = CGPoint(x: center.x - highlightOffset, y: center.y + highlightOffset)
            Self.drawRadialGradient(shading, from: highlight, radius: 0, to: center, radius: shadingRadius, in: context)
        }
    }

    /// Draws a radial gradient that ends in a circle containing its start, clipped to that
    /// circle's bounds. Unclipped, Core Graphics shades the whole clip area on every call, which
    /// makes a board of stones many times slower.
    private static func drawRadialGradient(
        _ gradient: CGGradient, from start: CGPoint, radius startRadius: CGFloat,
        to end: CGPoint, radius endRadius: CGFloat, in context: CGContext
    ) {
        context.saveGState()
        context.clip(to: square(around: end, radius: endRadius + 1))
        context.drawRadialGradient(
            gradient, startCenter: start, startRadius: startRadius, endCenter: end, endRadius: endRadius, options: []
        )
        context.restoreGState()
    }

    private func drawLastMoveMarker(
        at point: SGFPoint, on board: Board, layout: BoardLayout, palette: Palette, in context: CGContext
    ) {
        guard !layout.isTiny, let color = board[point], let center = layout.center(of: point) else { return }
        let markerColor = color == .black ? palette.markerOnBlack : palette.markerOnWhite
        if layout.isCompact {
            fillDiscs(at: [center], radius: layout.cell * 0.2, color: markerColor, in: context)
        } else {
            let width = max(1, layout.cell * 0.075)
            strokeCircles(at: [center], radius: layout.cell * 0.26, width: width, color: markerColor, in: context)
        }
    }

    private func fillDiscs(at centers: [CGPoint], radius: CGFloat, color: CGColor, in context: CGContext) {
        guard !centers.isEmpty else { return }
        for center in centers {
            context.addEllipse(in: Self.square(around: center, radius: radius))
        }
        context.setFillColor(color)
        context.fillPath()
    }

    private func strokeCircles(
        at centers: [CGPoint], radius: CGFloat, width: CGFloat, color: CGColor, in context: CGContext
    ) {
        guard !centers.isEmpty else { return }
        for center in centers {
            context.addEllipse(in: Self.square(around: center, radius: radius))
        }
        context.setLineWidth(width)
        context.setStrokeColor(color)
        context.strokePath()
    }

    static func square(around center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }
}
