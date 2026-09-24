import CoreGraphics
import Foundation
import SGFKit
import SGFRendering
import Testing

@Suite("Sizes")
struct SizeTests {
    /// Every square board from 2x2 to 52x52, and a few rectangular ones.
    private static let shapes: [(Int, Int)] = (2 ... 52).map { ($0, $0) } + [
        (19, 13), (13, 19), (19, 9), (52, 2), (2, 52), (9, 5), (52, 51), (25, 26), (3, 4), (1, 1), (1, 19),
    ]

    /// A board with stones on about half its points, a mix of both colors, so every kind of
    /// drawing is exercised.
    private static func crowdedBoard(_ size: BoardSize) -> Board {
        var board = Board(size: size)
        for column in 1 ... size.columns {
            for row in 1 ... size.rows where (column + 2 * row) % 4 < 2 {
                board.place((column * 7 + row * 3) % 5 < 2 ? .white : .black, at: SGFPoint(column: column, row: row))
            }
        }
        return board
    }

    @Test("Every size renders", arguments: BoardStyle.builtIn)
    func everySizeRenders(style: BoardStyle) throws {
        let renderers = [
            BoardRenderer(style: style),
            BoardRenderer(style: style, showsCoordinates: true, margin: 0.5),
        ]
        for (columns, rows) in Self.shapes {
            let size = try #require(BoardSize(columns: columns, rows: rows))
            let board = Self.crowdedBoard(size)
            let lastMove = board.stones(of: .black).first
            for side in [16, 32, 128, 512] {
                for renderer in renderers {
                    let imageSize = CGSize(width: side, height: side)
                    let image = try #require(renderer.makeImage(of: board, lastMove: lastMove, size: imageSize),
                                             "\(size) at \(side) px")
                    #expect(image.width == side && image.height == side)
                    // The middle of the image is always on the board. (A board thinner than a
                    // pixel is a one-pixel strip on one side of the middle line.)
                    let pixels = image.pixels
                    let middle = [(side / 2, side / 2), (side / 2 - 1, side / 2 - 1)]
                    #expect(middle.contains { pixels[$0.0, $0.1].alpha == 255 }, "\(size) at \(side) px")
                }
                let collection = try #require(renderers[0].makeCollectionImage(
                    of: board, size: CGSize(width: side, height: side)))
                #expect(collection.width == side)
            }
        }
    }

    @Test("Odd rects and scales", arguments: BoardStyle.builtIn)
    func oddRectsAndScales(style: BoardStyle) throws {
        let renderer = BoardRenderer(style: style, showsCoordinates: true)
        let board = Self.crowdedBoard(.standard)
        for (width, height, scale) in [(512.0, 64.0, 1.0), (40.0, 900.0, 1.0), (100.0, 100.0, 3.0), (33.3, 21.7, 2.0)] {
            let image = try #require(renderer.makeImage(of: board, size: CGSize(width: width, height: height), scale: scale))
            #expect(image.width == Int((width * scale).rounded()))
            #expect(image.height == Int((height * scale).rounded()))
        }
    }

    @Test func emptyAndHugeSizesMakeNoImage() {
        let renderer = BoardRenderer()
        let board = Board(size: .standard)
        #expect(renderer.makeImage(of: board, size: .zero) == nil)
        #expect(renderer.makeImage(of: board, size: CGSize(width: 100, height: -1)) == nil)
        #expect(renderer.makeImage(of: board, size: CGSize(width: 100, height: 100), scale: 0) == nil)
        #expect(renderer.makeImage(of: board, size: CGSize(width: 20000, height: 10)) == nil)
        #expect(renderer.makeImage(of: board, size: CGSize(width: CGFloat.nan, height: 10)) == nil)
    }

    @Test func drawingIntoAnEmptyRectDrawsNothing() throws {
        let context = try #require(CGContext(
            data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let renderer = BoardRenderer()
        #expect(renderer.draw(Board(size: .standard), in: context, rect: .zero).isNull)
        #expect(renderer.draw(Board(size: .standard), in: context, rect: .null).isNull)
        #expect(renderer.drawCollection(Board(size: .standard), in: context, rect: .zero).isNull)
    }

    @Test func collectionFrontBoardSitsAtTheTopLeft() throws {
        let context = try #require(CGContext(
            data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let rect = CGRect(x: 0, y: 0, width: 256, height: 256)
        let front = BoardRenderer().drawCollection(Board(size: .standard), in: context, rect: rect)
        // In the default user space, y points up: the front board touches the top and left
        // edges, and the stack behind it shows at the bottom and right.
        #expect(front.minX == 0)
        #expect(front.maxY == 256)
        #expect(front.width == front.height)
        #expect(front.width > 256 * 0.85 && front.width < 256)
        let pixels = try #require(context.makeImage()).pixels
        #expect(pixels[250, 250].alpha > 0, "the stack shows at the bottom right")
        #expect(pixels[250, 3].alpha == 0, "nothing at the top right")
    }

    @Test func stylesHaveStableIdentifiers() {
        #expect(BoardStyle.builtIn.map(\.identifier) == ["shaded", "flat"])
        #expect(BoardStyle(identifier: "flat") == .flat)
        #expect(BoardStyle(identifier: "shaded") == .shaded)
        #expect(BoardStyle(identifier: "kaya") == nil)
    }
}
