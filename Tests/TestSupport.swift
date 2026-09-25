import CoreGraphics
import Foundation
import ImageIO
import SGFKit
import Testing
import UniformTypeIdentifiers

/// Parses SGF text.
func collection(_ sgf: String, stopAfterFirstGame: Bool = false) -> SGFCollection {
    SGFParser.parse(Data(sgf.utf8), options: .init(stopAfterFirstGame: stopAfterFirstGame))
}

/// The first game of SGF text.
func game(_ sgf: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> SGFGame {
    try #require(collection(sgf).games.first, sourceLocation: sourceLocation)
}

/// A game on a board of a size with `count` moves and no captures: Black fills the even rows
/// from the top and White the odd ones, each leaving the last column empty, so every row keeps
/// a liberty.
func longGame(size: Int, moves count: Int, passAt passes: Set<Int> = []) -> String {
    var sgf = "(;GM[1]FF[4]SZ[\(size)]"
    let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    var blackIndex = 0
    var whiteIndex = 0
    for number in stride(from: 1, through: count, by: 1) {
        let isBlack = number % 2 == 1
        if passes.contains(number) {
            sgf += isBlack ? ";B[]" : ";W[]"
            continue
        }
        let index = isBlack ? blackIndex : whiteIndex
        let perRow = size - 1
        let row = (index / perRow) * 2 + (isBlack ? 0 : 1)
        let point = "\(letters[index % perRow])\(letters[row])"
        sgf += isBlack ? ";B[\(point)]" : ";W[\(point)]"
        if isBlack { blackIndex += 1 } else { whiteIndex += 1 }
    }
    return sgf + ")"
}

/// Synthetic files. None are real games, and none contain anyone else's commentary.
enum Fixtures {
    /// A made-up 19x19 game with every field the preview shows.
    static let fullInfo = """
        (;GM[1]FF[4]CA[UTF-8]SZ[19]KM[6.5]HA[0]RU[Japanese]GN[Fixture game]
        PB[Black Tester]BR[3d]PW[White Tester]WR[4d]BT[Team Kuro]WT[Team Shiro]
        EV[Fixture Cup]RO[2]DT[2024-03-17]PC[Nowhere]RE[W+2.5]
        GC[A game made up for tests.\nIt has two lines.]
        ;B[pd];W[dp];B[pp];W[dd];B[fq];W[cn])
        """

    /// John Mifsud's 3-stone handicap game against GNU Go, from the SGF Tools 1.x test files.
    static func johnVsGnu() throws -> URL {
        try #require(Bundle(for: BundleToken.self).url(forResource: "johnVsGnu", withExtension: "sgf"))
    }
}

private final class BundleToken {}

/// An sRGB bitmap whose premultiplied RGBA bytes can be read and written, row 0 at the top.
final class Bitmap {
    let width: Int
    let height: Int
    let context: CGContext
    let bytes: UnsafeMutableBufferPointer<UInt8>

    /// A clear bitmap of a size in pixels.
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        bytes = UnsafeMutableBufferPointer(
            start: context.data!.assumingMemoryBound(to: UInt8.self), count: width * height * 4
        )
    }

    /// The pixels of an image, or of the part of it in `rect`, in pixels from its top left.
    convenience init(_ image: CGImage, rect: CGRect? = nil) {
        let rect = rect ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
        self.init(width: Int(rect.width), height: Int(rect.height))
        context.draw(image, in: CGRect(x: -rect.minX, y: rect.maxY - CGFloat(image.height),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
    }

    var image: CGImage? { context.makeImage() }

    /// The four bytes of a pixel, from the offset of its first.
    func pixel(at offset: Int) -> SIMD4<Double> {
        SIMD4(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2]), Double(bytes[offset + 3]))
    }

    /// The four bytes of the pixel at a column and a row counted from the top.
    func pixel(x: Int, y: Int) -> SIMD4<Double> {
        pixel(at: (y * width + x) * 4)
    }

    func alpha(x: Int, y: Int) -> Int {
        Int(bytes[(y * width + x) * 4 + 3])
    }

    /// The relative brightness of an opaque pixel, from 0 to 1.
    func brightness(x: Int, y: Int) -> Double {
        let pixel = pixel(x: x, y: y)
        return (0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]) / 255
    }

    /// The average over all pixels of a value of their four bytes.
    func average(_ value: (SIMD4<Double>) -> Double) -> Double {
        var total = 0.0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            total += value(pixel(at: offset))
        }
        return total / Double(width * height)
    }
}

/// Writes an image to a PNG file.
func writePNG(_ image: CGImage, to url: URL) throws {
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

/// A random number generator that gives the same numbers for the same seed (SplitMix64), so that
/// tests of random choices can repeat them.
struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// A screensaver log that keeps its lines, for tests to check.
final class RecordingLog: SaverLogging, @unchecked Sendable {
    struct Line: Sendable {
        let level: SaverLogLevel
        let category: SaverLogCategory
        let message: String
        let path: String?
    }

    private let lock = NSLock()
    private var recorded: [Line] = []

    func log(_ level: SaverLogLevel, _ category: SaverLogCategory, _ message: String, path: String?) {
        lock.withLock { recorded.append(Line(level: level, category: category, message: message, path: path)) }
    }

    /// The messages of a category, optionally only those at a level.
    func messages(_ category: SaverLogCategory, level: SaverLogLevel? = nil) -> [String] {
        lock.withLock {
            recorded.filter { $0.category == category && (level == nil || $0.level == level) }.map(\.message)
        }
    }

    var lines: [Line] { lock.withLock { recorded } }
}
