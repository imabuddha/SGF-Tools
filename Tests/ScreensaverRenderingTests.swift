import CoreGraphics
import Foundation
import QuartzCore
import SGFKit
import Testing

/// Renders one screen's layers at chosen moments of a game, without a window, and checks their
/// pixels: black outside the board and the details, wood in the board, and light text in the
/// details.
///
/// When the environment variable `SGF_SCREENSAVER_SAMPLES` names a folder (with `xcodebuild test`,
/// set `TEST_RUNNER_SGF_SCREENSAVER_SAMPLES`), the images are written there as PNGs. When
/// `SGF_SCREENSAVER_THUMBNAIL` names a folder (`TEST_RUNNER_SGF_SCREENSAVER_THUMBNAIL`, set to
/// `"$PWD/Screensaver"` from the repository's folder, since the tests don't run there), the
/// screensaver's `thumbnail.png` and `thumbnail@2x.png` are drawn there.
@Suite("Screensaver: rendering")
@MainActor
struct ScreensaverRenderingTests {
    static let samples = ProcessInfo.processInfo.environment["SGF_SCREENSAVER_SAMPLES"]
    static let thumbnailFolder = ProcessInfo.processInfo.environment["SGF_SCREENSAVER_THUMBNAIL"]

    /// The moments the samples show: half faded in, after moves 1, 25, and 50, and fading out.
    static let moments: [(time: Double, name: String)] = [
        (1, "1-fading-in"), (3.5, "2-move-1"), (27.5, "3-move-25"), (52.5, "4-move-50"), (58, "5-fading-out"),
    ]

    static func johnVsGnu(as source: SaverGame.Source = .playlist) throws -> SaverGame {
        let game = try #require(try SGFCollection(contentsOf: Fixtures.johnVsGnu()).games.first)
        return try #require(SaverGame(game: game, source: source, identity: "johnVsGnu",
                                      hint: source == .own ? SaverGame.ownGameHint : nil, mustQualify: false,
                                      locale: Locale(identifier: "en_US")))
    }

    /// A screen's layers rendered at a time since the game started.
    struct Frame {
        let image: CGImage
        let prepared: PreparedGame
        let screen: CGSize
        let scale: CGFloat

        /// A rect of the screen, in points with y up, as pixels from the image's top left.
        func pixels(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX * scale, y: (screen.height - rect.maxY) * scale,
                   width: rect.width * scale, height: rect.height * scale).integral
        }

        /// The average of a value over a rect of the screen.
        func average(in rect: CGRect, _ value: (SIMD4<Double>) -> Double) -> Double {
            Bitmap(image, rect: pixels(rect)).average(value)
        }

        /// The brightest pixel in a rect of the screen, from 0 to 1.
        func brightest(in rect: CGRect) -> Double {
            let bitmap = Bitmap(image, rect: pixels(rect))
            var brightest = 0.0
            for y in 0 ..< bitmap.height {
                for x in 0 ..< bitmap.width { brightest = max(brightest, bitmap.brightness(x: x, y: y)) }
            }
            return brightest
        }
    }

    static func render(_ game: SaverGame, screen: CGSize, scale: CGFloat, seed: UInt64, at time: Double) throws -> Frame {
        var generator = SeededGenerator(seed: seed)
        let prepared = try #require(SaverScene.prepare(game, screen: screen, scale: scale, using: &generator))
        let root = CALayer()
        root.anchorPoint = .zero
        root.bounds = CGRect(origin: .zero, size: screen)
        let scene = SaverScene(rootLayer: root)
        scene.show(prepared)
        let state = prepared.timeline.state(at: time)
        scene.setBoard(SaverScene.boardImage(of: game, afterMoves: state.movesShown, side: prepared.layout.board.width,
                                             scale: scale), animated: false)
        scene.apply(state, at: time, animated: false)
        let bitmap = Bitmap(width: Int(screen.width * scale), height: Int(screen.height * scale))
        bitmap.context.scaleBy(x: scale, y: scale)
        root.render(in: bitmap.context)
        return Frame(image: try #require(bitmap.image), prepared: prepared, screen: screen, scale: scale)
    }

    static func write(_ image: CGImage, name: String) throws {
        guard let samples else { return }
        let folder = URL(fileURLWithPath: samples, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writePNG(image, to: folder.appendingPathComponent("\(name).png"))
    }

    @Test(arguments: [
        (CGSize(width: 1920, height: 1080), 1 as CGFloat, 1 as UInt64),
        (CGSize(width: 1728, height: 1117), 2, 2),
        (CGSize(width: 1080, height: 1920), 1, 3),
    ])
    func aScreen(screen: CGSize, scale: CGFloat, seed: UInt64) throws {
        let game = try Self.johnVsGnu()
        let playing = try Self.render(game, screen: screen, scale: scale, seed: seed, at: 27.5)
        let layout = playing.prepared.layout
        let board = layout.board
        let details = try #require(layout.details)
        #expect(playing.prepared.timeline.state(at: 27.5).movesShown == 25)

        // Black outside the board and the details: the corners, and between the two.
        let corner = CGRect(x: 0, y: 0, width: 8, height: 8)
        #expect(playing.average(in: corner) { $0[0] + $0[1] + $0[2] } < 1)
        let between: CGRect = switch layout.side {
        case .right: CGRect(x: board.maxX + 2, y: board.midY - 4, width: 8, height: 8)
        case .left: CGRect(x: board.minX - 10, y: board.midY - 4, width: 8, height: 8)
        case .above: CGRect(x: board.midX - 4, y: board.maxY + 2, width: 8, height: 8)
        case .below, nil: CGRect(x: board.midX - 4, y: board.minY - 10, width: 8, height: 8)
        }
        #expect(playing.average(in: between) { $0[0] + $0[1] + $0[2] } < 1)
        // Wood in the board: warm, and bright.
        let wood = board.insetBy(dx: board.width * 0.3, dy: board.height * 0.3)
        #expect(playing.average(in: wood) { ($0[0] - $0[2]) / 255 } > 0.1)
        #expect(playing.average(in: board) { ($0[0] + $0[1] + $0[2]) / 765 } > 0.35)
        // Light text in the details.
        #expect(playing.brightest(in: details) > 0.85)
        #expect(playing.average(in: details) { ($0[0] + $0[1] + $0[2]) / 765 } < 0.5, "text on black")

        // Half faded in, the board is about half as bright; the details have barely begun.
        let fadingIn = try Self.render(game, screen: screen, scale: scale, seed: seed, at: 1)
        let full = playing.average(in: wood) { $0[1] }
        let half = fadingIn.average(in: wood) { $0[1] }
        #expect(abs(half / full - 0.5) < 0.08)
        #expect(fadingIn.brightest(in: details) < 0.2)
        // Faded out, all black.
        let gone = try Self.render(game, screen: screen, scale: scale, seed: seed, at: 59.5)
        #expect(gone.average(in: CGRect(origin: .zero, size: screen)) { $0[0] + $0[1] + $0[2] } < 0.01)

        for (time, name) in Self.moments {
            let frame = time == 27.5 ? playing : try Self.render(game, screen: screen, scale: scale, seed: seed, at: time)
            try Self.write(frame.image, name: "screen-\(Int(screen.width))x\(Int(screen.height))@\(Int(scale))x-\(name)")
        }
    }

    @Test func aPreview() throws {
        let screen = CGSize(width: 300, height: 190)
        let frame = try Self.render(try Self.johnVsGnu(), screen: screen, scale: 2, seed: 1, at: 27.5)
        #expect(frame.prepared.layout.isPreview)
        #expect(frame.prepared.details == nil)
        let board = frame.prepared.layout.board
        #expect(abs(board.midX - 150) < 0.01 && abs(board.width - 171) < 0.01)
        #expect(frame.average(in: CGRect(x: 0, y: 0, width: 50, height: 190)) { $0[0] + $0[1] + $0[2] } < 1)
        #expect(frame.average(in: board.insetBy(dx: 50, dy: 50)) { ($0[0] - $0[2]) / 255 } > 0.1)
        for (time, name) in Self.moments {
            let frame = try Self.render(try Self.johnVsGnu(), screen: screen, scale: 2, seed: 1, at: time)
            try Self.write(frame.image, name: "preview-300x190@2x-\(name)")
        }
    }

    @Test func theOwnGameSaysToOpenSGFTools() throws {
        let game = try Self.johnVsGnu(as: .own)
        let frame = try Self.render(game, screen: CGSize(width: 2560, height: 1440), scale: 1, seed: 4, at: 30)
        let details = try #require(frame.prepared.layout.details)
        #expect(details.height > 6 * 1440 * Look.screensaverDetailFontFraction)
        try Self.write(frame.image, name: "own-game-2560x1440@1x")
    }

    @Test func otherBoardSizes() throws {
        for (size, name) in [("9", "9x9"), ("13", "13x13"), ("19:13", "19x13")] {
            let sgf = "(;GM[1]SZ[\(size)]PB[Kuro]BR[1d]PW[Shiro]WR[2d]RE[B+R]EV[Fixture Cup]DT[2024-03-17]"
                + fillerMoves(60, columns: Int(size.prefix { $0 != ":" }) ?? 19) + ")"
            let game = try #require(SaverGame(game: try game(sgf), source: .playlist, identity: name,
                                              locale: Locale(identifier: "en_US")))
            let frame = try Self.render(game, screen: CGSize(width: 1920, height: 1080), scale: 1, seed: 7, at: 27.5)
            let board = frame.prepared.layout.board
            #expect(frame.average(in: board.insetBy(dx: board.width * 0.3, dy: board.height * 0.45)) { ($0[0] - $0[2]) / 255 } > 0.1)
            try Self.write(frame.image, name: "board-\(name)-1920x1080@1x-move-25")
        }
    }

    /// The screensaver picker's thumbnail, 90 by 58 points: a screen of that shape after move 50
    /// of johnVsGnu, scaled down.
    @Test func thumbnail() throws {
        let screen = CGSize(width: 1800, height: 1160)
        let frame = try Self.render(try Self.johnVsGnu(), screen: screen, scale: 1, seed: 2, at: 52.5)
        for (scale, name) in [(1, "thumbnail.png"), (2, "thumbnail@2x.png")] {
            let bitmap = Bitmap(width: 90 * scale, height: 58 * scale)
            bitmap.context.interpolationQuality = .high
            bitmap.context.draw(frame.image, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
            let image = try #require(bitmap.image)
            #expect(image.width == 90 * scale && image.height == 58 * scale)
            if let folder = Self.thumbnailFolder {
                try writePNG(image, to: URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(name))
            }
            try Self.write(image, name: name.replacingOccurrences(of: ".png", with: ""))
        }
    }
}
