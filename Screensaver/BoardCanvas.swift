import CoreGraphics
import Foundation
import SGFKit
import SGFRendering

/// A rect of whole pixels in a board's image, counted from its top left.
struct PixelRect: Sendable, Hashable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var area: Int { width * height }
    var isEmpty: Bool { width <= 0 || height <= 0 }

    /// The part of this rect inside another, which may be empty.
    func intersection(_ other: PixelRect) -> PixelRect {
        let minX = max(x, other.x), minY = max(y, other.y)
        let maxX = min(x + width, other.x + other.width), maxY = min(y + height, other.y + other.height)
        return PixelRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    func intersects(_ other: PixelRect) -> Bool { !intersection(other).isEmpty }

    /// The smallest rect holding both.
    func union(_ other: PixelRect) -> PixelRect {
        let minX = min(x, other.x), minY = min(y, other.y)
        return PixelRect(x: minX, y: minY, width: max(x + width, other.x + other.width) - minX,
                         height: max(y + height, other.y + other.height) - minY)
    }
}

/// A square of the board that changed with a move, and its new pixels.
struct BoardTile: Sendable {
    /// The tile's place in the canvas's grid, row by row from the top left.
    let index: Int
    let rect: PixelRect
    let image: CGImage
}

/// What changed on the board from one number of moves to another: the tiles to replace.
struct BoardUpdate: Sendable {
    /// The moves on the board before, and after.
    let from: Int
    let moves: Int
    let tiles: [BoardTile]
    /// How long the drawing took, in milliseconds, and the pixels it covered.
    let milliseconds: Double
    let drawnPixels: Int
}

/// One game's board at one screen's size and scale, kept as a bitmap that each move redraws
/// only where it changes (see `docs/screensaver.md`, section 3).
///
/// The first position is drawn in full, as `BoardRenderer.makeImage` draws it, on black. After
/// that, a move redraws small squares around each point that changed, clipped from the same
/// full drawing, so the bitmap is always the position's full drawing, pixel for pixel (a test
/// checks it over whole games with captures). A point changes when a stone is played or
/// captured there, or when the last-move ring leaves or reaches it. Its square reaches
/// ``reach`` cells from the point's center, past the stone (0.475 cells) and its shadow (about
/// 0.63 cells down and to the right).
///
/// The board is cut into a fixed grid of tiles of about 1.5 cells. A move's update holds only
/// the tiles its squares touch, copied out of the bitmap, so the scene fades a few small
/// images instead of the whole board.
///
/// The bitmap is opaque BGRA, the layout Core Animation uses as is. A canvas isn't safe to use
/// from two threads at once: the player uses it only on its drawing queue.
final class BoardCanvas: @unchecked Sendable {
    /// How far a changed point's square reaches from its center, in cells, before a margin of
    /// two pixels for anti-aliasing.
    static let reach: CGFloat = 0.75

    /// The side of a tile, in cells.
    static let tileCells: CGFloat = 1.5

    let game: SaverGame
    /// The board's side, in points, and the screen's backing scale.
    let side: CGFloat
    let scale: CGFloat
    /// The bitmap's size in pixels.
    let width: Int
    let height: Int
    /// The side of a tile, in pixels, and the grid's columns and rows.
    let tileSide: Int
    let tileColumns: Int
    let tileRows: Int
    /// The number of moves the bitmap shows, once drawn.
    private(set) var moves: Int?

    private let context: CGContext
    private let renderer = BoardRenderer(style: Look.screensaverStyle, margin: Look.screensaverMargin)
    /// The distance between lines, and the lines' centers, in pixels with y up, as the renderer
    /// lays them out.
    private let cell: CGFloat
    private let columnCenters: [CGFloat]
    private let rowCenters: [CGFloat]

    /// A canvas for a game's board, or `nil` if the size is empty or too large. Nothing is drawn
    /// until ``draw(afterMoves:)``.
    init?(game: SaverGame, side: CGFloat, scale: CGFloat) {
        guard side.isFinite, scale.isFinite, side > 0, scale > 0 else { return nil }
        let pixels = (side * scale).rounded()
        guard (1 ... 16384).contains(pixels), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: Int(pixels), height: Int(pixels), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        self.game = game
        self.side = side
        self.scale = scale
        width = Int(pixels)
        height = Int(pixels)
        self.context = context

        // BoardLayout's arithmetic, for a board with no coordinates, fitted in the whole bitmap.
        let columns = game.boardSize.columns, rows = game.boardSize.rows
        let border = 0.5 + max(0, Look.screensaverMargin)
        let spanX = CGFloat(columns - 1), spanY = CGFloat(rows - 1)
        let cell = min(pixels / (spanX + 2 * border), pixels / (spanY + 2 * border))
        let lineWidth = max(1, (cell / 30).rounded())
        let center = pixels / 2
        self.cell = cell
        columnCenters = (0 ..< columns).map { (center + (CGFloat($0) - spanX / 2) * cell - lineWidth / 2).rounded() + lineWidth / 2 }
        rowCenters = (0 ..< rows).map { (center + (spanY / 2 - CGFloat($0)) * cell - lineWidth / 2).rounded() + lineWidth / 2 }
        tileSide = max(16, Int((cell * Self.tileCells).rounded()))
        tileColumns = (width + tileSide - 1) / tileSide
        tileRows = (height + tileSide - 1) / tileSide
    }

    // MARK: - Drawing

    /// Brings the bitmap to the position after a number of moves: in full the first time, and
    /// after that only in the squares around the points that changed.
    ///
    /// - Returns: The pixels drawn.
    @discardableResult
    func draw(afterMoves target: Int) -> Int {
        let target = min(max(0, target), game.moveCount)
        let rects = moves.map { redrawnRects(from: $0, to: target) } ?? [PixelRect(x: 0, y: 0, width: width, height: height)]
        moves = target
        let board = game.positions[target]
        let lastMove = Look.screensaverMarksLastMove ? game.lastMoves[target] : nil
        // One rect at a time: a clip of several rects is a mask, which cuts the renderer's own
        // clips a level differently here and there; one rect clips as the board's own rect does.
        for rect in rects {
            context.saveGState()
            // In device space, before the scale, so that the clip's edges are on whole pixels.
            context.clip(to: CGRect(x: rect.x, y: height - rect.y - rect.height, width: rect.width, height: rect.height))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // As BoardRenderer.makeImage does.
            context.scaleBy(x: CGFloat(width) / side, y: CGFloat(height) / side)
            renderer.draw(board, lastMove: lastMove, in: context, rect: CGRect(x: 0, y: 0, width: side, height: side))
            context.restoreGState()
        }
        return rects.reduce(0) { $0 + $1.area }
    }

    /// Draws the position after a number of moves, and returns the tiles that differ from the
    /// position after `from`.
    func update(from: Int, to target: Int) -> BoardUpdate {
        let start = ContinuousClock.now
        let drawn = draw(afterMoves: target)
        let tiles = tiles(touching: changedRects(from: from, to: target)).compactMap(tile(_:))
        return BoardUpdate(from: from, moves: target, tiles: tiles,
                           milliseconds: (ContinuousClock.now - start) / .milliseconds(1), drawnPixels: drawn)
    }

    /// The whole bitmap as an image. Drawing on the canvas afterward copies the bitmap first, so
    /// the image keeps what it shows.
    func image() -> CGImage? {
        context.makeImage()
    }

    // MARK: - Where a move changes the board

    /// The points whose drawing differs between two numbers of moves: where the stones differ,
    /// and where the last-move ring was and is.
    func changedPoints(from: Int, to target: Int) -> [SGFPoint] {
        guard from != target else { return [] }
        let before = game.positions[from], after = game.positions[target]
        var points = Set<SGFPoint>()
        for row in 1 ... game.boardSize.rows {
            for column in 1 ... game.boardSize.columns {
                let point = SGFPoint(column: column, row: row)
                if before[point] != after[point] { points.insert(point) }
            }
        }
        if Look.screensaverMarksLastMove {
            for ring in [game.lastMoves[from], game.lastMoves[target]] { if let ring { points.insert(ring) } }
        }
        return points.sorted()
    }

    /// The squares to redraw between two numbers of moves, in the bitmap.
    func changedRects(from: Int, to target: Int) -> [PixelRect] {
        changedPoints(from: from, to: target).compactMap(square(around:))
    }

    /// The rects to redraw between two numbers of moves: the changed squares, grown to hold
    /// whole every stone shading and shadow they touch.
    ///
    /// Core Graphics shades a gradient cut by the clip a level or two differently from the same
    /// gradient whole, so a square that cut through a neighbor's stone would leave it slightly
    /// off. Grown this way, every gradient drawn is drawn whole, as the full drawing draws it.
    /// Only the changed squares differ from before, so only their tiles are shown.
    func redrawnRects(from: Int, to target: Int) -> [PixelRect] {
        let squares = changedRects(from: from, to: target)
        guard !squares.isEmpty else { return [] }
        let board = game.positions[target]
        var stones: [PixelRect] = []
        for row in 1 ... game.boardSize.rows {
            for column in 1 ... game.boardSize.columns {
                let point = SGFPoint(column: column, row: row)
                if board[point] != nil, let extent = gradients(of: point) { stones.append(extent) }
            }
        }
        return squares.map { square in
            var rect = square
            var grown = true
            while grown {
                grown = false
                for stone in stones where rect.intersects(stone) && rect.intersection(stone) != stone {
                    rect = rect.union(stone)
                    grown = true
                }
            }
            return rect
        }
    }

    /// The rect that a stone's shading and shadow gradients are clipped to, as the renderer
    /// draws them, with a pixel to spare, in the bitmap.
    func gradients(of point: SGFPoint) -> PixelRect? {
        guard (1 ... columnCenters.count).contains(point.column), (1 ... rowCenters.count).contains(point.row) else {
            return nil
        }
        let x = columnCenters[point.column - 1], y = rowCenters[point.row - 1]
        // BoardRenderer: stones of 0.475 cells, shaded to max(r / 2, r - 0.75); shadows offset
        // by (0.07, -0.09) cells, reaching 1.12 radii; each gradient clipped a pixel beyond.
        let radius = cell * 0.475
        let shading = max(radius * 0.5, radius - 0.75) + 1
        let shadow = radius * 1.12 + 1
        let shadowX = x + cell * 0.07, shadowY = y - cell * 0.09
        let minX = Int((min(x - shading, shadowX - shadow) - 1).rounded(.down))
        let maxX = Int((max(x + shading, shadowX + shadow) + 1).rounded(.up))
        let minY = Int((min(y - shading, shadowY - shadow) - 1).rounded(.down))
        let maxY = Int((max(y + shading, shadowY + shadow) + 1).rounded(.up))
        let rect = PixelRect(x: minX, y: height - maxY, width: maxX - minX, height: maxY - minY)
        let clipped = rect.intersection(PixelRect(x: 0, y: 0, width: width, height: height))
        return clipped.isEmpty ? nil : clipped
    }

    /// The square around a point that its stone, shadow, and ring can reach, in the bitmap.
    func square(around point: SGFPoint) -> PixelRect? {
        guard (1 ... columnCenters.count).contains(point.column), (1 ... rowCenters.count).contains(point.row) else {
            return nil
        }
        let x = columnCenters[point.column - 1], y = rowCenters[point.row - 1]
        let half = Self.reach * cell + 2
        let minX = Int((x - half).rounded(.down)), maxX = Int((x + half).rounded(.up))
        let minY = Int((y - half).rounded(.down)), maxY = Int((y + half).rounded(.up))
        // From pixel space, y up, to the bitmap's rows from the top.
        let rect = PixelRect(x: minX, y: height - maxY, width: maxX - minX, height: maxY - minY)
        let clipped = rect.intersection(PixelRect(x: 0, y: 0, width: width, height: height))
        return clipped.isEmpty ? nil : clipped
    }

    // MARK: - Tiles

    /// The rect of a tile, in the bitmap.
    func tileRect(_ index: Int) -> PixelRect {
        let x = (index % tileColumns) * tileSide, y = (index / tileColumns) * tileSide
        return PixelRect(x: x, y: y, width: min(tileSide, width - x), height: min(tileSide, height - y))
    }

    /// The tiles that any of some rects touch, in order.
    func tiles(touching rects: [PixelRect]) -> [Int] {
        var indices = Set<Int>()
        for rect in rects where !rect.isEmpty {
            for row in rect.y / tileSide ... (rect.y + rect.height - 1) / tileSide {
                for column in rect.x / tileSide ... (rect.x + rect.width - 1) / tileSide {
                    indices.insert(row * tileColumns + column)
                }
            }
        }
        return indices.sorted()
    }

    /// A tile's pixels, copied out of the bitmap into an image of their own.
    private func tile(_ index: Int) -> BoardTile? {
        let rect = tileRect(index)
        guard let data = context.data else { return nil }
        let source = data.assumingMemoryBound(to: UInt8.self)
        let rowBytes = rect.width * 4
        var bytes = Data(count: rowBytes * rect.height)
        bytes.withUnsafeMutableBytes { buffer in
            guard let target = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for row in 0 ..< rect.height {
                (target + row * rowBytes).update(from: source + (rect.y + row) * context.bytesPerRow + rect.x * 4,
                                                 count: rowBytes)
            }
        }
        guard let provider = CGDataProvider(data: bytes as CFData), let space = context.colorSpace,
              let image = CGImage(width: rect.width, height: rect.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: rowBytes, space: space, bitmapInfo: context.bitmapInfo,
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return BoardTile(index: index, rect: rect, image: image)
    }
}
