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

/// A game on a board of a size with `count` moves and no captures (see
/// ``fillerMoves(_:columns:firstRow:whiteFirst:passes:)``). Moves listed in `passes` are passes.
func longGame(size: Int, moves count: Int, passAt passes: Set<Int> = []) -> String {
    "(;GM[1]FF[4]SZ[\(size)]" + fillerMoves(count, columns: size, passes: passes) + ")"
}

/// Moves for a synthetic game, as SGF nodes, with no captures: Black fills every other row and
/// White the rows between, from `firstRow` down, each leaving the last column empty, so every
/// row keeps a liberty. Moves listed in `passes` (counting from 1) are passes.
func fillerMoves(_ count: Int, columns: Int = 19, firstRow: Int = 1, whiteFirst: Bool = false,
                 passes: Set<Int> = []) -> String {
    let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    var sgf = ""
    var placed = [0, 0]  // black, white
    for number in stride(from: 1, through: count, by: 1) {
        let isBlack = (number % 2 == 1) != whiteFirst
        let property = isBlack ? "B" : "W"
        if passes.contains(number) {
            sgf += ";\(property)[]"
            continue
        }
        let index = placed[isBlack ? 0 : 1]
        let perRow = columns - 1
        let row = firstRow - 1 + (index / perRow) * 2 + (isBlack ? 0 : 1)
        sgf += ";\(property)[\(letters[index % perRow])\(letters[row])]"
        placed[isBlack ? 0 : 1] += 1
    }
    return sgf
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

/// A clock that tests move by hand.
final class TestClock: @unchecked Sendable {
    var now: Double

    init(_ now: Double) {
        self.now = now
    }
}

/// A thread-safe count, for closures that tests hand to the code under test.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.withLock { count += 1 }
    }

    var value: Int { lock.withLock { count } }
}

/// A thread-safe list of what happened, in order, for closures that tests hand to the code
/// under test.
final class Recorder<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Element] = []

    func append(_ element: Element) {
        lock.withLock { elements.append(element) }
    }

    var values: [Element] { lock.withLock { elements } }
}

/// A temporary folder, removed when the test ends.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("SGFToolsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        // Make anything a test locked readable again, so it can be removed.
        if let items = FileManager.default.enumerator(atPath: url.path) {
            for case let item as String in items { chmod(url.appendingPathComponent(item).path, 0o755) }
        }
        chmod(url.path, 0o755)
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes a file in the folder and returns its path.
    @discardableResult
    func write(_ text: String, to name: String) throws -> String {
        let file = url.appendingPathComponent(name)
        try Data(text.utf8).write(to: file)
        return file.path
    }
}

// MARK: - The screensaver's games

/// A game that qualifies for the screensaver: both players named, and `moves` moves.
func namedGame(size: String = "19", moves: Int = 60, extraRoot: String = "") -> String {
    "(;GM[1]FF[4]SZ[\(size)]PB[Black Tester]BR[3d]PW[White Tester]WR[5d]RE[W+R]EV[Fixture Cup]"
        + "DT[2009-05-01]\(extraRoot)" + fillerMoves(moves, columns: Int(size.prefix { $0 != ":" }) ?? 19) + ")"
}

/// A playlist holding lines, with a header.
func playlistText(_ lines: [String], found: Int? = nil, made: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> String {
    Playlist.text(of: .init(made: made, found: found ?? lines.count, games: lines.count))
        + lines.map { $0 + "\n" }.joined()
}

/// Reads for the builder and direct mode that answer by path: "denied", "locked", "gone",
/// "cloud", and "problem" give those outcomes, "slow" waits for `release` and then gives a game,
/// and anything else is a game with `moves` moves.
func scriptedReader(release: DispatchSemaphore? = nil, reads: Counter? = nil,
                    moves: @escaping @Sendable (_ path: String) -> Int = { _ in 30 }) -> GameFileReader {
    var reader = GameFileReader()
    reader.status = { path in
        if path.contains("gone") { return .failure(.init(code: ENOENT)) }
        return .success(.init(inode: 1, size: 1000, modified: [0, 0], isDataless: path.contains("cloud")))
    }
    reader.readPrefix = { path, _ in
        reads?.increment()
        if path.contains("denied") { return .failure(.init(code: EPERM)) }
        if path.contains("locked") { return .failure(.init(code: EACCES)) }
        if path.contains("problem") { return .success(Data("(;AB[dd];W[pp])".utf8)) }
        if path.contains("slow") { release?.wait() }
        return .success(Data(namedGame(moves: moves(path)).utf8))
    }
    return reader
}

/// Writes a playlist of `count` games, from files named `prefix 0.sgf` and on, to a URL, replacing
/// any file there.
func writePlaylist(_ count: Int, prefix: String = "game", to url: URL) throws {
    let game = try game(namedGame(moves: 30))
    let lines = (0 ..< count).compactMap { Playlist.line(for: game, url: URL(fileURLWithPath: "/Games/\(prefix) \($0).sgf")) }
    try Data(playlistText(lines).utf8).write(to: url, options: .atomic)
}

/// The screensaver's own game, from the test bundle, which carries johnVsGnu.sgf as the
/// screensaver's does.
let ownGame: @Sendable () -> SaverGame? = { SaverGame.own(in: Bundle(for: RecordingLog.self)) }
