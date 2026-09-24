import CoreGraphics
import Foundation
import SGFKit
import SGFRendering
import Testing

/// Renders boards and checks their pixels. Grid lines are found in images of empty flat boards
/// (black lines on a light board); the layout is the same in every style.
@Suite("Pixels")
struct PixelTests {
    private static let flatBoard = Pixels.Color(red: 246, green: 227, blue: 184, alpha: 255)

    private func square(_ side: CGFloat) -> CGSize { CGSize(width: side, height: side) }

    private func grid(_ size: BoardSize, in imageSize: CGSize) throws -> DetectedGrid {
        let image = try #require(BoardRenderer(style: .flat).makeImage(of: Board(size: size), size: imageSize))
        return DetectedGrid(image.pixels)
    }

    /// Whether a color is a plausible wood color: warm, and neither dark nor washed out.
    private func isWood(_ color: Pixels.Color) -> Bool {
        color.alpha == 255 && color.red > color.green && color.green > color.blue
            && (150 ... 250).contains(color.red) && color.blue < 170 && color.brightness > 0.5
    }

    @Test("One line per column and row", arguments: [
        (19, 19), (13, 13), (9, 9), (3, 3), (2, 2), (19, 13), (13, 19), (19, 5), (7, 3),
    ])
    func oneLinePerColumnAndRow(columns: Int, rows: Int) throws {
        let size = try #require(BoardSize(columns: columns, rows: rows))
        let grid = try grid(size, in: square(512))
        #expect(grid.columns.count == columns)
        #expect(grid.rows.count == rows)
    }

    @Test("Rectangular boards have square cells", arguments: [
        (19, 13, 512.0, 512.0), (13, 19, 512.0, 512.0), (19, 9, 400.0, 600.0),
        (9, 19, 700.0, 300.0), (52, 20, 600.0, 300.0), (5, 17, 257.0, 419.0),
    ])
    func squareCells(columns: Int, rows: Int, width: Double, height: Double) throws {
        let size = try #require(BoardSize(columns: columns, rows: rows))
        let grid = try grid(size, in: CGSize(width: width, height: height))
        try #require(grid.columns.count == columns && grid.rows.count == rows)
        let first = grid.center(column: 1, row: 1)
        let last = grid.center(column: columns, row: rows)
        let across = (last.x - first.x) / Double(columns - 1)
        let down = (last.y - first.y) / Double(rows - 1)
        #expect(abs(across - down) < 0.25, "cell \(across) x \(down)")
        // Lines are rounded to whole pixels one by one, so neighbors differ by at most a pixel.
        for column in 1 ..< columns {
            let step = grid.center(column: column + 1, row: 1).x - grid.center(column: column, row: 1).x
            #expect(abs(step - across) <= 1)
        }
        for row in 1 ..< rows {
            let step = grid.center(column: 1, row: row + 1).y - grid.center(column: 1, row: row).y
            #expect(abs(step - down) <= 1)
        }
        // The board is centered in the image.
        let image = try #require(BoardRenderer(style: .flat).makeImage(of: Board(size: size), size: CGSize(width: width, height: height)))
        let pixels = image.pixels
        let middleRow = pixels.height / 2
        let middleColumn = pixels.width / 2
        let left = (0 ..< pixels.width).first { pixels[$0, middleRow].alpha > 0 } ?? -1
        let right = (0 ..< pixels.width).last { pixels[$0, middleRow].alpha > 0 } ?? -1
        let top = (0 ..< pixels.height).first { pixels[middleColumn, $0].alpha > 0 } ?? -1
        let bottom = (0 ..< pixels.height).last { pixels[middleColumn, $0].alpha > 0 } ?? -1
        #expect(abs(left - (pixels.width - 1 - right)) <= 1)
        #expect(abs(top - (pixels.height - 1 - bottom)) <= 1)
    }

    @Test("Lines land on whole pixels", arguments: [1.0, 2.0, 3.0, 1.5])
    func linesLandOnWholePixels(scale: Double) throws {
        for (columns, rows) in [(19, 19), (13, 9)] {
            let size = try #require(BoardSize(columns: columns, rows: rows))
            let pointSize = square(512 / scale)
            let image = try #require(BoardRenderer(style: .flat).makeImage(of: Board(size: size), size: pointSize, scale: scale))
            #expect(image.width == 512)
            try expectCrispLines(image.pixels, columns: columns, rows: rows)
        }
    }

    @Test func linesLandOnWholePixelsInAnOddRect() throws {
        // A rect that starts and ends between pixels, in a context scaled by 2.
        let context = try bitmapContext(width: 600, height: 500)
        context.scaleBy(x: 2, y: 2)
        let drawn = BoardRenderer(style: .flat).draw(Board(size: .standard), in: context,
                                                     rect: CGRect(x: 10.3, y: 7.6, width: 240.45, height: 230.2))
        let image = try #require(context.makeImage())
        try expectCrispLines(image.pixels, columns: 19, rows: 19)
        // The rect it returns is the board, on whole pixels, inside the rect it was given.
        #expect(drawn.minX * 2 == (drawn.minX * 2).rounded())
        #expect(drawn.maxY * 2 == (drawn.maxY * 2).rounded())
        #expect(abs(drawn.width - drawn.height) < 0.51)
        #expect(drawn.minY >= 7.6 - 0.25 && drawn.maxY <= 7.6 + 230.2 + 0.25)
    }

    /// Checks that between two lines, every pixel across the grid is either the board color or
    /// solid black: no line is smeared over two pixels by anti-aliasing.
    private func expectCrispLines(_ pixels: Pixels, columns: Int, rows: Int) throws {
        let grid = DetectedGrid(pixels)
        try #require(grid.columns.count == columns && grid.rows.count == rows)
        let black = Pixels.Color(red: 0, green: 0, blue: 0, alpha: 255)
        func isClean(_ color: Pixels.Color) -> Bool {
            color.distance(to: black) <= 1 || color.distance(to: Self.flatBoard) <= 1
        }
        let y = Int(((grid.rows[0].center + grid.rows[1].center) / 2).rounded(.down))
        let x = Int(((grid.columns[0].center + grid.columns[1].center) / 2).rounded(.down))
        let xs = Int(grid.columns.first!.center) ... Int(grid.columns.last!.center)
        let ys = Int(grid.rows.first!.center) ... Int(grid.rows.last!.center)
        let smearedAcross = xs.filter { !isClean(pixels[$0, y]) }
        let smearedDown = ys.filter { !isClean(pixels[x, $0]) }
        #expect(smearedAcross.isEmpty, "smeared pixels at x = \(smearedAcross) on row \(y)")
        #expect(smearedDown.isEmpty, "smeared pixels at y = \(smearedDown) in column \(x)")
        // And each inner line is the same whole number of pixels wide.
        #expect(Set(grid.columns.dropFirst().dropLast().map(\.width)).count <= 1)
        #expect(Set(grid.rows.dropFirst().dropLast().map(\.width)).count <= 1)
    }

    @Test("Stones and empty points", arguments: BoardStyle.builtIn)
    func stonesAndEmptyPoints(style: BoardStyle) throws {
        let black = ["dd", "pp", "jj", "aa", "ss", "ab"]
        let white = ["pd", "dp", "jk", "sa", "as", "ba"]
        let empty = ["cc", "qc", "gg", "mm", "fo", "no", "jr"]
        let position = board(black: black, white: white)
        let image = try #require(BoardRenderer(style: style).makeImage(of: position, size: square(512)))
        let pixels = image.pixels
        let grid = try grid(.standard, in: square(512))
        let cell = (grid.columns.last!.center - grid.columns.first!.center) / 18

        func sample(_ sgf: String, dx: Double = 0, dy: Double = 0) -> Pixels.Color {
            let point = pt(sgf)
            let center = grid.center(column: point.column, row: point.row)
            return pixels[(center.x + dx * cell, center.y + dy * cell)]
        }
        for point in black {
            #expect(sample(point).brightness < 0.35, "black at \(point): \(sample(point))")
            #expect(sample(point, dx: 0.25, dy: 0.25).brightness < 0.35, "black at \(point)")
            #expect(sample(point, dx: -0.25, dy: 0.2).brightness < 0.35, "black at \(point)")
        }
        for point in white {
            #expect(sample(point).brightness > 0.8, "white at \(point): \(sample(point))")
            #expect(sample(point, dx: 0.25, dy: 0.25).brightness > 0.7, "white at \(point)")
            #expect(sample(point, dx: -0.25, dy: 0.2).brightness > 0.7, "white at \(point)")
        }
        for point in empty {
            for (dx, dy) in [(0.3, 0.3), (-0.3, 0.3), (0.3, -0.3), (-0.3, -0.3)] {
                let color = sample(point, dx: dx, dy: dy)
                if style == .flat {
                    #expect(color.distance(to: Self.flatBoard) <= 1, "empty \(point): \(color)")
                } else {
                    #expect(isWood(color), "empty \(point): \(color)")
                }
            }
        }
    }

    @Test("Star points", arguments: BoardStyle.builtIn)
    func starPoints(style: BoardStyle) throws {
        let shapes = [(3, 3), (4, 4), (5, 5), (6, 6), (7, 7), (9, 9), (11, 11), (12, 12), (13, 13),
                      (19, 19), (21, 21), (25, 25), (52, 52), (19, 13), (19, 9), (9, 5), (13, 21)]
        for (columns, rows) in shapes {
            let size = try #require(BoardSize(columns: columns, rows: rows))
            // Cells of about 40 pixels, so a star point is clearly bigger than a line crossing.
            let side = CGFloat(40 * (max(columns, rows) + 1))
            let image = try #require(BoardRenderer(style: style).makeImage(of: Board(size: size), size: square(side)))
            let pixels = image.pixels
            let grid = try grid(size, in: square(side))
            try #require(grid.columns.count == columns && grid.rows.count == rows)
            var found: Set<SGFPoint> = []
            for column in 2 ..< columns {
                for row in 2 ..< rows {
                    let center = grid.center(column: column, row: row)
                    // Just off the lines, diagonally: board color, unless a star point covers it.
                    let corners = [(2.0, 2.0), (-2.0, 2.0), (2.0, -2.0), (-2.0, -2.0)]
                    if corners.allSatisfy({ pixels[(center.x + $0.0, center.y + $0.1)].brightness < 0.45 }) {
                        found.insert(SGFPoint(column: column, row: row))
                    }
                }
            }
            #expect(found == Set(size.starPoints), "\(size) \(style)")
        }
    }

    @Test("A rectangular board leaves the rest transparent", arguments: BoardStyle.builtIn)
    func rectangularBoardIsTransparentAround(style: BoardStyle) throws {
        let size = try #require(BoardSize(columns: 19, rows: 13))
        let pixels = try #require(BoardRenderer(style: style).makeImage(of: Board(size: size), size: square(256))).pixels
        #expect(pixels[128, 5].alpha == 0)
        #expect(pixels[128, 250].alpha == 0)
        #expect(pixels[128, 128].alpha == 255)
        #expect(pixels[2, 128].alpha == 255)
    }

    @Test("The board is upright in a flipped context", arguments: [false, true])
    func uprightWhenFlipped(flipped: Bool) throws {
        let context = try bitmapContext(width: 200, height: 200)
        if flipped {
            context.translateBy(x: 0, y: 200)
            context.scaleBy(x: 1, y: -1)
        }
        let size = try #require(BoardSize(9))
        // A black stone at the top left (A9) and a white one at the bottom right (J1).
        BoardRenderer(style: .flat).draw(board(size, black: ["aa"], white: ["ii"]), in: context,
                                         rect: CGRect(x: 0, y: 0, width: 200, height: 200))
        let pixels = try #require(context.makeImage()).pixels
        let grid = try grid(size, in: square(200))
        #expect(pixels[grid.center(column: 1, row: 1)].brightness < 0.2)
        #expect(pixels[grid.center(column: 9, row: 9)].brightness > 0.9)
        #expect(pixels[grid.center(column: 9, row: 1)].brightness < 0.2, "a bare corner crossing is black too")
        #expect(pixels[(grid.center(column: 9, row: 9).x - 6, grid.center(column: 9, row: 9).y - 6)].brightness > 0.9)
    }

    @Test("Last-move marker", arguments: BoardStyle.builtIn)
    func lastMoveMarker(style: BoardStyle) throws {
        let position = board(black: ["dd"], white: ["pp"])
        let renderer = BoardRenderer(style: style)
        let plain = try #require(renderer.makeImage(of: position, size: square(512))).pixels
        let onBlack = try #require(renderer.makeImage(of: position, lastMove: pt("dd"), size: square(512))).pixels
        let onWhite = try #require(renderer.makeImage(of: position, lastMove: pt("pp"), size: square(512))).pixels
        let onEmpty = try #require(renderer.makeImage(of: position, lastMove: pt("jj"), size: square(512))).pixels
        let grid = try grid(.standard, in: square(512))
        let cell = (grid.columns.last!.center - grid.columns.first!.center) / 18
        // The ring is about a quarter cell from the center: light on black, dark on white.
        let dd = grid.center(column: 4, row: 4)
        let pp = grid.center(column: 16, row: 16)
        let ringOnBlack = (dd.x + 0.26 * cell, dd.y)
        let ringOnWhite = (pp.x + 0.26 * cell, pp.y)
        #expect(plain[ringOnBlack].brightness < 0.35)
        #expect(onBlack[ringOnBlack].brightness > 0.7)
        #expect(plain[ringOnWhite].brightness > 0.7)
        #expect(onWhite[ringOnWhite].brightness < 0.35)
        // Nothing is marked on an empty point.
        let jj = grid.center(column: 10, row: 10)
        #expect(onEmpty[(jj.x + 0.26 * cell, jj.y + 0.26 * cell)] .distance(to: plain[(jj.x + 0.26 * cell, jj.y + 0.26 * cell)]) == 0)
    }

    @Test("Coordinates and margin make the grid smaller", arguments: BoardStyle.builtIn)
    func coordinatesAndMargin(style: BoardStyle) throws {
        func gridSpan(_ renderer: BoardRenderer) throws -> Double {
            let image = try #require(renderer.makeImage(of: Board(size: .standard), size: square(512)))
            // Find the grid by its dark lines; in the shaded style too, the lines are darker than
            // the wood.
            let grid = DetectedGrid(image.pixels, darkBelow: style == .flat ? 0.5 : 0.45)
            return grid.columns.last!.center - grid.columns.first!.center
        }
        let plain = try gridSpan(BoardRenderer(style: style))
        let margin = try gridSpan(BoardRenderer(style: style, margin: 0.5))
        let labels = try gridSpan(BoardRenderer(style: style, showsCoordinates: true))
        let allSides = try gridSpan(BoardRenderer(style: style, showsCoordinates: true, coordinateSides: .all))
        // 18 cells plus a half cell each side; then plus 0.5 cell each side, or a 0.9-cell band
        // on one side (left and bottom) or both.
        #expect(abs(plain / margin - 20 / 19) < 0.01)
        #expect(abs(plain / labels - 19.9 / 19) < 0.01)
        #expect(abs(plain / allSides - 20.8 / 19) < 0.01)
        // Too small for readable labels: no room is made for them.
        let small = try #require(BoardRenderer(style: style, showsCoordinates: true)
            .makeImage(of: Board(size: .standard), size: square(64)))
        let smallPlain = try #require(BoardRenderer(style: style).makeImage(of: Board(size: .standard), size: square(64)))
        #expect(small.pixels.bytes == smallPlain.pixels.bytes)
    }

    @Test("Edge stones reach the edge of the board", arguments: BoardStyle.builtIn)
    func edgeStonesReachTheEdge(style: BoardStyle) throws {
        // A black stone on each side's edge line: A10, K19, T10, and K1.
        let position = board(black: ["aj", "ja", "sj", "js"])
        let image = try #require(BoardRenderer(style: style).makeImage(of: position, size: square(400)))
        let pixels = image.pixels
        let cell = 400.0 / 19
        // Within a tenth of a cell of each edge, the middle of each side is stone.
        for (x, y) in [(0.1 * cell, 200.0), (200, 0.1 * cell), (400 - 0.1 * cell, 200), (200, 400 - 0.1 * cell)] {
            #expect(pixels[(x, y)].brightness < 0.3, "at \(x), \(y)")
        }
    }

    @Test("Coordinates go outside the board, on the left and bottom by default")
    func coordinatesOutsideTheBoard() throws {
        let side = 400.0
        let renderer = BoardRenderer(style: .flat, showsCoordinates: true)
        let pixels = try #require(renderer.makeImage(of: Board(size: .standard), size: square(side))).pixels
        let cell = side / 19.9
        let band = 0.9 * cell
        func opaqueCount(x: ClosedRange<Double>, y: ClosedRange<Double>) -> Int {
            var count = 0
            for py in Int(y.lowerBound) ... Int(y.upperBound) {
                for px in Int(x.lowerBound) ... Int(x.upperBound) where pixels[px, py].alpha > 0 { count += 1 }
            }
            return count
        }
        // The board fills the top right; the bands on the left and bottom hold only the labels.
        #expect(pixels[Int(side) - 2, 1].alpha == 255)
        #expect(pixels[Int(band) + 2, 1].alpha == 255)
        #expect(pixels[1, 1].alpha == 0)
        #expect(pixels[Int(side) - 2, Int(side) - 1].alpha == 0)
        #expect(opaqueCount(x: 0 ... band - 2, y: 0 ... side - band - 1) > 0, "row numbers on the left")
        #expect(opaqueCount(x: band + 1 ... side - 1, y: side - band + 2 ... side - 1) > 0, "column letters below")
        // Nothing in the corner between the two bands.
        #expect(opaqueCount(x: 0 ... band - 2, y: side - band + 2 ... side - 1) == 0)
        // The labels are in the style's color unless another is given.
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        var light = renderer
        light.coordinateColor = white
        let lightPixels = try #require(light.makeImage(of: Board(size: .standard), size: square(side))).pixels
        var darkest = 1.0, lightest = 0.0
        for py in 0 ..< Int(side - band) {
            for px in 0 ..< Int(band - 2) {
                if pixels[px, py].alpha >= 200 { darkest = min(darkest, pixels[px, py].brightness) }
                if lightPixels[px, py].alpha >= 200 { lightest = max(lightest, lightPixels[px, py].brightness) }
            }
        }
        #expect(darkest < 0.2)
        #expect(lightest > 0.9)
    }

    @Test func collectionsHaveNoCoordinates() throws {
        let position = board(black: ["dd"])
        let size = square(400)
        // Flat, because Core Graphics doesn't draw the shaded stones' drop shadows identically
        // every time when tests run in parallel (differences of up to 16 levels, near the stone).
        let with = try #require(BoardRenderer(style: .flat, showsCoordinates: true).makeCollectionImage(of: position, size: size))
        let without = try #require(BoardRenderer(style: .flat).makeCollectionImage(of: position, size: size))
        #expect(with.pixels.bytes == without.pixels.bytes)
    }
}
