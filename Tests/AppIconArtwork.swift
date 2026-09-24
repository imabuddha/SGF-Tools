import CoreGraphics
import Foundation
import ImageIO
import SGFKit
import SGFRendering
import Testing
import UniformTypeIdentifiers

/// The artwork of the app icon, `App/AppIcon.icon`: the top-right corner of the position that
/// the thumbnail of John Mifsud's 2009 game against GNU Go shows, drawn by the thumbnails'
/// renderer in their style.
///
/// The icon is an Icon Composer document. Its `icon.json` stacks two layers on a slate
/// background: the board, with its wood and lines, and above it the stones with their shadows.
/// Each is a group of its own, so macOS lights the board's edges as glass and leaves the stones
/// as the renderer draws them. The board runs off the icon at the left and bottom; at the top
/// and right, its edges and the background show.
///
/// The layers are PNGs in `App/AppIcon.icon/Assets`. This suite draws and checks them on every
/// test run, and writes them when the environment variable `SGF_APP_ICON_ASSETS` names a folder
/// (with `xcodebuild test`, set `TEST_RUNNER_SGF_APP_ICON_ASSETS`):
///
///     TEST_RUNNER_SGF_APP_ICON_ASSETS="$PWD/App/AppIcon.icon/Assets" xcodebuild \
///         -project SGFTools.xcodeproj -scheme "SGF Tools" test -only-testing:SGFToolsTests/AppIconArtwork
@Suite("App icon artwork")
struct AppIconArtwork {
    static let directory = ProcessInfo.processInfo.environment["SGF_APP_ICON_ASSETS"]

    /// The side of the icon's canvas and of each layer, in pixels.
    static let side = 1024

    /// The distance between lines, in pixels. At this size, columns 11 to 19 and rows 1 to 9
    /// show, so the icon is a corner of the board with stones large enough to read at 32 pixels.
    static let cell: CGFloat = 104

    /// The background between the board's top and right edges and the canvas's, in pixels.
    static let inset: CGFloat = 96

    @Test func drawsTheLayers() throws {
        let game = try #require(try SGFCollection(contentsOf: Fixtures.johnVsGnu()).games.first)
        let position = OpeningPosition(game: game)
        #expect(position.movesShown == 50)
        let layers = try #require(Self.layers(of: position.board))

        for image in [layers.board, layers.stones] {
            #expect(image.width == Self.side && image.height == Self.side)
        }
        // The canvas's top-right corner is background, left for the icon's fill. The top-left of
        // the canvas is board; the stones layer is clear there, as it is between the stones.
        let board = Bitmap(layers.board)
        let stones = Bitmap(layers.stones)
        #expect(board.alpha(x: Self.side - 10, y: 10) == 0)
        #expect(board.alpha(x: 10, y: Int(Self.inset) + 10) == 255)
        #expect(stones.alpha(x: 10, y: Int(Self.inset) + 10) == 0)
        // Stones are opaque: a white one at column 12, row 4, and a black one at 14, 4.
        let white = Self.center(column: 12, row: 4)
        let black = Self.center(column: 14, row: 4)
        #expect(stones.alpha(x: white.x, y: white.y) == 255)
        #expect(stones.brightness(x: white.x, y: white.y) > 0.8)
        #expect(stones.alpha(x: black.x, y: black.y) == 255)
        #expect(stones.brightness(x: black.x, y: black.y) < 0.3)
        // Only the stones: the board just beyond a stone's left edge, where no shadow falls, is
        // left to the board layer.
        #expect(stones.alpha(x: white.x - Int(Self.cell / 2), y: white.y) == 0)
        // Below and to the right of a stone is its shadow, dark and partly transparent.
        let shadow = stones.alpha(x: black.x + Int(Self.cell * 0.36), y: black.y + Int(Self.cell * 0.44))
        #expect((40 ... 220).contains(shadow))

        if let directory = Self.directory {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.writePNG(layers.board, to: folder.appendingPathComponent("board.png"))
            try Self.writePNG(layers.stones, to: folder.appendingPathComponent("stones.png"))
        }
    }

    // MARK: - Drawing

    /// The board's rect in the canvas, with y pointing up: a whole board, most of it off the
    /// canvas, with its top-right corner `inset` from the canvas's.
    static func boardRect(for size: BoardSize) -> CGRect {
        let width = cell * CGFloat(size.columns)
        let height = cell * CGFloat(size.rows)
        let canvas = CGFloat(side)
        return CGRect(x: canvas - inset - width, y: canvas - inset - height, width: width, height: height)
    }

    /// The center of a point in the canvas, in whole pixels from the top left.
    static func center(column: Int, row: Int, in rect: CGRect = boardRect(for: .standard)) -> (x: Int, y: Int) {
        let x = rect.minX + (CGFloat(column) - 0.5) * cell
        let y = rect.maxY - (CGFloat(row) - 0.5) * cell
        return (Int(x.rounded(.down)), side - 1 - Int(y.rounded(.down)))
    }

    /// The two layers: the empty board, and the stones with their shadows on a clear background.
    ///
    /// The renderer draws stones and shadows only on its wood, so the stones layer is taken from
    /// two drawings, the board with the position and without it. Where the stones are, it takes
    /// the drawing of the position as it is. Elsewhere, it keeps only what the position darkens,
    /// the shadows, as a dark color over the empty board, so that the layers together are the
    /// renderer's drawing again.
    static func layers(of position: Board) -> (board: CGImage, stones: CGImage)? {
        let renderer = BoardRenderer(style: Look.thumbnailStyle, margin: Look.thumbnailMargin)
        let rect = boardRect(for: position.size)
        let empty = Bitmap()
        renderer.draw(Board(size: position.size), in: empty.context, rect: rect)
        let full = Bitmap()
        renderer.draw(position, in: full.context, rect: rect)
        let stonesOnly = Bitmap()
        let radius = stoneRadius(renderer: renderer, empty: empty, rect: rect)
        for color in StoneColor.allCases {
            for point in position.stones(of: color) {
                let x = rect.minX + (CGFloat(point.column) - 0.5) * cell
                let y = rect.maxY - (CGFloat(point.row) - 0.5) * cell
                stonesOnly.context.addEllipse(
                    in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)
                )
            }
        }
        stonesOnly.context.clip()
        renderer.draw(position, in: stonesOnly.context, rect: rect)

        let stones = Bitmap()
        for offset in stride(from: 0, to: stones.bytes.count, by: 4) {
            // Premultiplied: the stone, over the shadow.
            let shadow = shadowPixel(over: empty.pixel(at: offset), making: full.pixel(at: offset))
            let drawn = stonesOnly.pixel(at: offset)
            let value = drawn + shadow * (1 - drawn[3] / 255)
            for channel in 0 ..< 4 {
                stones.bytes[offset + channel] = UInt8(max(0, min(255, value[channel].rounded())))
            }
        }
        guard let board = empty.image, let stonesImage = stones.image else { return nil }
        return (board, stonesImage)
    }

    /// The radius of the renderer's stones, in pixels, measured on a drawing of a lone stone:
    /// from its center along its row to the left, where no shadow falls, to the first pixel that
    /// the stone leaves as the empty board has it, less half a pixel.
    private static func stoneRadius(renderer: BoardRenderer, empty: Bitmap, rect: CGRect) -> CGFloat {
        let point = SGFPoint(column: 15, row: 5)
        var board = Board(size: .standard)
        board.place(.white, at: point)
        let drawing = Bitmap()
        renderer.draw(board, in: drawing.context, rect: rect)
        let center = center(column: point.column, row: point.row, in: rect)
        var x = center.x
        while x > 0 {
            let offset = (center.y * side + x) * 4
            let difference = drawing.pixel(at: offset) - empty.pixel(at: offset)
            if max(difference.max(), -difference.min()) <= 2 { break }
            x -= 1
        }
        return CGFloat(center.x - x) - 0.5
    }

    /// The darkest color, premultiplied, that turns an opaque pixel `below` into `result` when
    /// drawn over it, or clear if `result` isn't darker.
    private static func shadowPixel(over below: SIMD4<Double>, making result: SIMD4<Double>) -> SIMD4<Double> {
        guard below[3] == 255, result[3] == 255 else { return .zero }
        // The alpha that darkens the channel that darkens most; that channel's color is black.
        var alpha = 0.0
        for channel in 0 ..< 3 where below[channel] > 0 {
            alpha = max(alpha, (below[channel] - result[channel]) / below[channel])
        }
        alpha = min(1, alpha)
        guard alpha > 0 else { return .zero }
        var color = result - below * (1 - alpha)
        for channel in 0 ..< 3 {
            color[channel] = max(0, min(255 * alpha, color[channel]))
        }
        color[3] = 255 * alpha
        return color
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

/// A clear canvas-sized sRGB bitmap whose premultiplied RGBA bytes can be read and written,
/// row 0 at the top.
private final class Bitmap {
    let context: CGContext
    let bytes: UnsafeMutableBufferPointer<UInt8>

    init() {
        let side = AppIconArtwork.side
        context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        bytes = UnsafeMutableBufferPointer(
            start: context.data!.assumingMemoryBound(to: UInt8.self), count: side * side * 4
        )
    }

    convenience init(_ image: CGImage) {
        self.init()
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    var image: CGImage? { context.makeImage() }

    /// The four bytes of a pixel, from the offset of its first.
    func pixel(at offset: Int) -> SIMD4<Double> {
        SIMD4(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2]), Double(bytes[offset + 3]))
    }

    func alpha(x: Int, y: Int) -> Int {
        Int(bytes[(y * AppIconArtwork.side + x) * 4 + 3])
    }

    /// The relative brightness of an opaque pixel, from 0 to 1.
    func brightness(x: Int, y: Int) -> Double {
        let offset = (y * AppIconArtwork.side + x) * 4
        return (0.2126 * Double(bytes[offset]) + 0.7152 * Double(bytes[offset + 1])
            + 0.0722 * Double(bytes[offset + 2])) / 255
    }
}
