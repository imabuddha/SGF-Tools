import CoreGraphics
import Foundation
import Metal
import QuartzCore
import SGFKit
import SGFRendering
import Testing

/// The board drawn a move at a time, and shown a few tiles at a time: the same pixels as the
/// whole board drawn afresh, and the same fades as the whole board faded.
///
/// These are regression guards: they show that the incremental drawing and the tiles give
/// exactly what the full drawing gives, not that the full drawing is right, which the rendering
/// tests check.
@Suite("Screensaver: drawing a move at a time")
@MainActor
struct ScreensaverCanvasTests {
    /// A game's pixels as sRGB bytes, RGBA, from the top left.
    static func bytes(_ image: CGImage?) throws -> Data {
        let image = try #require(image)
        let bitmap = Bitmap(width: image.width, height: image.height)
        bitmap.context.setBlendMode(.copy)
        bitmap.context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(buffer: bitmap.bytes)
    }

    /// How two images' bytes differ, for a failure's message: the pixels that differ, the
    /// largest difference, and the rect they're in, from the top left. (Comparing them in
    /// `#expect` itself would print megabytes.)
    static func difference(_ one: Data, _ other: Data, width: Int) -> String {
        guard one != other else { return "none" }
        guard one.count == other.count else { return "sizes \(one.count) and \(other.count)" }
        var count = 0, largest = 0, minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        one.withUnsafeBytes { a in
            other.withUnsafeBytes { b in
                var pixel = -1
                for index in 0 ..< a.count where a[index] != b[index] {
                    largest = max(largest, abs(Int(a[index]) - Int(b[index])))
                    guard index / 4 != pixel else { continue }
                    pixel = index / 4
                    count += 1
                    minX = min(minX, pixel % width)
                    maxX = max(maxX, pixel % width)
                    minY = min(minY, pixel / width)
                    maxY = max(maxY, pixel / width)
                }
            }
        }
        return "\(count) pixels, by up to \(largest), in x \(minX)-\(maxX), y \(minY)-\(maxY)"
    }

    static func saverGame(_ sgf: String) throws -> SaverGame {
        try #require(SaverGame(game: try game(sgf), source: .playlist, identity: "test", mustQualify: false))
    }

    /// The games: fights with many captures on three sizes, a rectangular board, passes, and
    /// johnVsGnu's handicap stones.
    static func games() throws -> [(name: String, game: SaverGame)] {
        [
            ("19x19 fights", try saverGame(capturingGame(size: 19, seed: 11, alwaysCapturing: true))),
            ("13x13 fights", try saverGame(capturingGame(size: 13, seed: 12, alwaysCapturing: true))),
            ("9x9 fights", try saverGame(capturingGame(size: 9, seed: 13, alwaysCapturing: true))),
            ("19x13", try saverGame(namedGame(size: "19:13", moves: 50))),
            ("passes", try saverGame(longGame(size: 19, moves: 50, passAt: [7, 8, 20, 21, 22, 50]))),
            ("johnVsGnu", try ScreensaverRenderingTests.johnVsGnu()),
        ]
    }

    /// The number of stones captured over a game.
    static func captures(in game: SaverGame) -> Int {
        game.positions.last.map { $0.capturedBlackStones + $0.capturedWhiteStones } ?? 0
    }

    @Test func theFightsHaveCaptures() throws {
        for (name, game) in try Self.games().prefix(3) {
            #expect(game.moveCount == 50, "\(name)")
            // 5, 23, and 15 stones.
            #expect(Self.captures(in: game) >= 5, "\(name): \(Self.captures(in: game)) captured")
        }
    }

    /// Move by move, and in jumps as late ticks make them, the canvas's bitmap is byte for byte
    /// the full drawing of the same position, and the tiles laid over the first board rebuild it.
    nonisolated static let sizes: [(side: CGFloat, scale: CGFloat)] = [(928.8, 2), (171, 2), (700.3, 1)]

    @Test(arguments: sizes)
    func incrementalDrawingEqualsTheFullDrawing(side: CGFloat, scale: CGFloat) throws {
        var generator = SeededGenerator(seed: 21)
        for (name, game) in try Self.games() {
            let canvas = try #require(BoardCanvas(game: game, side: side, scale: scale))
            #expect(canvas.draw(afterMoves: 0) == canvas.width * canvas.height)
            // What the screen shows: the first board, with each update's tiles copied over it.
            var shown = try Self.bytes(canvas.image())
            var moves = 0
            while moves < game.moveCount {
                let target = min(game.moveCount, moves + (Int.random(in: 0 ..< 4, using: &generator) == 0 ? 3 : 1))
                let update = canvas.update(from: moves, to: target)
                let full = try Self.bytes(SaverScene.boardImage(of: game, afterMoves: target, side: side, scale: scale))
                let drawn = try Self.bytes(canvas.image())
                let squares = canvas.redrawnRects(from: moves, to: target).map { "\($0.x),\($0.y) \($0.width)x\($0.height)" }
                #expect(drawn == full, Comment(rawValue: "\(name) at \(side)@\(scale)x: moves \(moves) to \(target) drawn: "
                    + "\(Self.difference(drawn, full, width: canvas.width)); squares \(squares)"))
                for tile in update.tiles {
                    let pixels = try Self.bytes(tile.image)
                    let rowBytes = tile.rect.width * 4
                    for row in 0 ..< tile.rect.height {
                        let start = ((tile.rect.y + row) * canvas.width + tile.rect.x) * 4
                        shown.replaceSubrange(start ..< start + rowBytes, with: pixels[row * rowBytes ..< (row + 1) * rowBytes])
                    }
                }
                #expect(shown == full, Comment(rawValue: "\(name) at \(side)@\(scale)x: moves \(moves) to \(target) shown: "
                    + Self.difference(shown, full, width: canvas.width)))
                moves = target
            }
        }
    }

    /// The whole board as the canvas draws it is the renderer's own image on black.
    @Test func theCanvasDrawsWhatTheRendererDraws() throws {
        let game = try Self.games()[0].game
        let renderer = BoardRenderer(style: Look.screensaverStyle, margin: Look.screensaverMargin)
        for (side, scale) in [(928.8 as CGFloat, 2 as CGFloat), (500, 1)] {
            let image = try #require(renderer.makeImage(of: game.positions[30], lastMove: game.lastMoves[30],
                                                        size: CGSize(width: side, height: side), scale: scale))
            let onBlack = Bitmap(width: image.width, height: image.height)
            onBlack.context.setFillColor(CGColor(gray: 0, alpha: 1))
            onBlack.context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            onBlack.context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let canvas = try Self.bytes(SaverScene.boardImage(of: game, afterMoves: 30, side: side, scale: scale))
            let reference = Data(buffer: onBlack.bytes)
            #expect(reference == canvas, "\(Self.difference(reference, canvas, width: image.width))")
        }
        let rectangular = try Self.games()[3].game
        let image = try #require(SaverScene.boardImage(of: rectangular, afterMoves: 10, side: 400, scale: 1))
        #expect(image.alphaInfo == .noneSkipLast, "opaque")
        let corner = Bitmap(image, rect: CGRect(x: 0, y: 0, width: 4, height: 4))
        #expect(corner.average { $0[0] + $0[1] + $0[2] } == 0, "black beside a rectangular board")
    }

    /// A move's squares and tiles are a small part of the board.
    @Test func aMoveTouchesAFewTiles() throws {
        let game = try Self.games()[0].game
        let canvas = try #require(BoardCanvas(game: game, side: 928.8, scale: 2))
        canvas.draw(afterMoves: 0)
        let board = canvas.width * canvas.height
        var tiles = 0
        var drawn = 0
        for moves in 1 ... game.moveCount {
            let update = canvas.update(from: moves - 1, to: moves)
            let area = update.tiles.reduce(0) { $0 + $1.rect.area }
            tiles += update.tiles.count
            let changed = canvas.changedPoints(from: moves - 1, to: moves).count
            #expect(area <= changed * 9 * canvas.tileSide * canvas.tileSide, "at move \(moves)")
            drawn += update.drawnPixels
        }
        #expect(Double(drawn) / Double(game.moveCount) < 0.2 * Double(board), "\(drawn / game.moveCount) pixels drawn a move")
        let average = Double(tiles) / Double(game.moveCount) * Double(canvas.tileSide * canvas.tileSide) / Double(board)
        #expect(average < 0.08, "\(average) of the board a move")
    }

    // MARK: - The scene

    static func prepared(_ game: SaverGame, screen: CGSize = CGSize(width: 1728, height: 1117), scale: CGFloat = 2)
        throws -> PreparedGame
    {
        var generator = SeededGenerator(seed: 3)
        return try #require(SaverScene.prepare(game, screen: screen, scale: scale, using: &generator))
    }

    static func scene(screen: CGSize = CGSize(width: 1728, height: 1117)) -> SaverScene {
        let root = CALayer()
        root.anchorPoint = .zero
        root.bounds = CGRect(origin: .zero, size: screen)
        return SaverScene(rootLayer: root)
    }

    @Test func aMomentIsOneCommitOrNone() throws {
        let game = try Self.games()[0].game
        var prepared = try Self.prepared(game)
        let canvas = try #require(prepared.canvas)
        prepared.canvas = nil
        let scene = Self.scene()
        scene.show(prepared)
        let timeline = prepared.timeline
        let frame = scene.boardFrame
        #expect(frame.minX * 2 == (frame.minX * 2).rounded() && frame.minY * 2 == (frame.minY * 2).rounded(), "on whole pixels")
        #expect(frame.width * 2 == CGFloat(canvas.width), "pixel for pixel")

        var commits = scene.stats.commits
        scene.apply(timeline.state(at: 0.1), at: 0.1, animated: true)
        #expect(scene.stats.commits == commits + 1, "the fade-in")
        commits = scene.stats.commits
        scene.apply(timeline.state(at: 0.2), at: 0.2, animated: true)
        #expect(scene.stats.commits == commits, "nothing changed, so nothing is committed")
        scene.apply(timeline.state(at: timeline.detailsFadeInEnd + 0.1), at: timeline.detailsFadeInEnd + 0.1, animated: true)
        commits = scene.stats.commits

        // A move with its fades: one commit, a few tiles.
        let time = timeline.time(ofMove: 1)
        let update = canvas.update(from: 0, to: 1)
        scene.apply(timeline.state(at: time), at: time, animated: true, board: update)
        #expect(scene.stats.commits == commits + 1)
        #expect(scene.tileCount == update.tiles.count && update.tiles.count <= 9)
        let second = canvas.update(from: 1, to: 2)
        scene.apply(timeline.state(at: time + 0.5), at: time + 0.5, animated: true, board: second)
        #expect(scene.tileCount == Set(update.tiles.map(\.index) + second.tiles.map(\.index)).count)

        // The fade-out with tiles over the board fades the game as a group; after the board is
        // whole again, it doesn't.
        let fadeOut = timeline.fadeOutStart + 0.05
        scene.apply(timeline.state(at: fadeOut), at: fadeOut, animated: true)
        #expect(scene.fadesAsGroup)
        scene.show(prepared)
        #expect(!scene.fadesAsGroup && scene.tileCount == 0)
        scene.apply(timeline.state(at: time), at: time, animated: true, board: canvas.update(from: 0, to: 3))
        scene.setBoard(canvas.image())
        #expect(scene.tileCount == 0)
        scene.apply(timeline.state(at: fadeOut), at: fadeOut, animated: true)
        #expect(!scene.fadesAsGroup)
    }

    // MARK: - Rendered offscreen

    /// Renders layer trees with a `CARenderer` into a Metal texture that can be read.
    final class Renderer {
        let renderer: CARenderer
        let texture: any MTLTexture
        let queue: any MTLCommandQueue

        init?(layer: CALayer, size: CGSize) {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: Int(size.width), height: Int(size.height), mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
            renderer.layer = layer
            renderer.bounds = CGRect(origin: .zero, size: size)
            self.texture = texture
            self.queue = queue
        }

        /// The whole layer tree rendered at a media time, as BGRA bytes.
        func render(at time: Double) -> [UInt8] {
            renderer.beginFrame(atTime: time, timeStamp: nil)
            renderer.addUpdate(renderer.bounds)
            renderer.render()
            renderer.endFrame()
            if let buffer = queue.makeCommandBuffer() {
                buffer.commit()
                buffer.waitUntilCompleted()
            }
            var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
            texture.getBytes(&bytes, bytesPerRow: texture.width * 4,
                             from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            return bytes
        }
    }

    /// The largest difference of any byte.
    static func largestDifference(_ one: [UInt8], _ other: [UInt8]) -> Int {
        zip(one, other).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
    }

    /// Mid-fade, a move's tiles look as the whole board faded to the next position looked, and
    /// the fade-out without group opacity looks as it did with it. Rendered by Core Animation
    /// offscreen, at 1x, on a screen that holds just the board and the details.
    @Test func theFadesLookAsTheyDid() throws {
        let screen = CGSize(width: 1000, height: 640)
        let game = try Self.games()[0].game
        var prepared = try Self.prepared(game, screen: screen, scale: 1)
        let canvas = try #require(prepared.canvas)
        prepared.canvas = nil
        let timeline = prepared.timeline

        // The new scene, at move 11, and the old way: one board layer with the whole image.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scene = Self.scene(screen: screen)
        scene.show(prepared)
        let held = timeline.time(ofMove: 11) + 0.25
        scene.apply(timeline.state(at: held), at: held, animated: false)
        canvas.draw(afterMoves: 11)
        scene.setBoard(canvas.image())
        let old = CALayer()
        old.anchorPoint = .zero
        old.bounds = CGRect(origin: .zero, size: screen)
        old.backgroundColor = CGColor(gray: 0, alpha: 1)
        let oldGame = CALayer()
        oldGame.frame = old.bounds
        let oldBoard = CALayer()
        oldBoard.frame = scene.boardFrame
        oldBoard.contents = canvas.image()
        let oldDetails = CALayer()
        oldDetails.frame = SaverScene.aligned(prepared.layout.details ?? .zero,
                                              pixels: prepared.details.map { ($0.width, $0.height) }, scale: 1)
        oldDetails.contents = prepared.details
        oldGame.addSublayer(oldBoard)
        oldGame.addSublayer(oldDetails)
        old.addSublayer(oldGame)
        CATransaction.commit()
        guard let new = Renderer(layer: scene.rootLayer, size: screen), let reference = Renderer(layer: old, size: screen) else {
            Issue.record("No Metal device")
            return
        }
        #expect(Self.largestDifference(new.render(at: CACurrentMediaTime()), reference.render(at: CACurrentMediaTime())) == 0,
                "held, the same")

        // Moves 12 to 14, each committed together with the old way's fade of the whole board.
        for moves in 12 ... 14 {
            let update = canvas.update(from: moves - 1, to: moves)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let time = timeline.time(ofMove: moves) + 0.01
            scene.apply(timeline.state(at: time), at: time, animated: true, board: update)
            let transition = CATransition()
            transition.type = .fade
            transition.duration = Look.screensaverMoveFade
            oldBoard.add(transition, forKey: "move")
            oldBoard.contents = canvas.image()
            CATransaction.commit()
            let start = CACurrentMediaTime()
            for offset in [0.03, 0.1, 0.15, 0.22, 0.29, 0.4] {
                let difference = Self.largestDifference(new.render(at: start + offset), reference.render(at: start + offset))
                #expect(difference <= 2, "move \(moves), \(offset) s into its fade: \(difference)")
            }
        }

        // The fade-out: the board whole again, the game layer fading without group opacity; the
        // old way with it.
        canvas.draw(afterMoves: 14)
        scene.setBoard(canvas.image())
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fadeOut = timeline.fadeOutStart
        scene.apply(timeline.state(at: fadeOut), at: fadeOut, animated: true)
        oldGame.allowsGroupOpacity = true
        oldGame.opacity = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = Look.screensaverFadeOut
        oldGame.add(fade, forKey: "fade")
        CATransaction.commit()
        #expect(!scene.fadesAsGroup)
        let start = CACurrentMediaTime()
        for offset in [0.2, 1.0, 1.7] {
            let difference = Self.largestDifference(new.render(at: start + offset), reference.render(at: start + offset))
            #expect(difference <= 2, "\(offset) s into the fade-out: \(difference)")
        }
    }
}
