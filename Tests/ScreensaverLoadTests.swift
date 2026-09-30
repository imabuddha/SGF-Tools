import CoreGraphics
import Foundation
import Metal
import QuartzCore
import Testing

/// Measures what one screen asks of Core Animation and of its drawing, with a clock the test
/// moves and games made in code (never the real library), so that a change to the rendering can
/// be compared before and after (see `docs/screensaver.md`, section 3).
///
/// It counts, per second of each phase of a game: the transactions committed, the pixels
/// uploaded as layers' contents, the area that the moves' fades animate, and the boards drawn.
/// A probe then renders the layer tree offscreen with a `CARenderer`, 60 frames a second, and
/// measures each frame's damaged area and time, as a stand-in for WindowServer's work.
///
/// When the environment variable `SGF_SCREENSAVER_LOAD` names a file (with `xcodebuild test`,
/// set `TEST_RUNNER_SGF_SCREENSAVER_LOAD`), the report is appended to it.
@Suite("Screensaver: load", .serialized)
@MainActor
struct ScreensaverLoadTests {
    static let reportFile = ProcessInfo.processInfo.environment["SGF_SCREENSAVER_LOAD"]

    /// Where a moment falls in a game.
    enum Phase: String, CaseIterable {
        /// From the first move to half a second after the last.
        case moves
        /// From a second after the last move to the fade-out.
        case holding
        /// The fades and the black between games.
        case other
    }

    /// What a screen did in each phase.
    struct Load {
        var seconds: [Phase: Double] = [:]
        var scene: [Phase: SaverScene.Stats] = [:]
        var player: [Phase: SaverPlayer.Stats] = [:]
        var movesShown = 0
        var boardPixels = 0

        mutating func add(_ phase: Phase, seconds: Double, scene: SaverScene.Stats, player: SaverPlayer.Stats) {
            self.seconds[phase, default: 0] += seconds
            self.scene[phase, default: .init()] = self.scene[phase, default: .init()] + scene
            self.player[phase, default: .init()] = self.player[phase, default: .init()] + player
        }
    }

    static let games = [capturingGame(seed: 1), capturingGame(seed: 2), capturingGame(size: 13, seed: 3)]

    /// Lets the drawing and the picking finish.
    static func settle(_ player: SaverPlayer) async {
        for _ in 0 ..< 1000 where player.hasWorkUnderWay {
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(!player.hasWorkUnderWay, "the drawing finished")
    }

    static func makePlayer(screen: CGSize, scale: CGFloat, clock: TestClock) throws -> SaverPlayer {
        let root = CALayer()
        root.anchorPoint = .zero
        root.bounds = CGRect(origin: .zero, size: screen)
        return SaverPlayer(scene: SaverScene(rootLayer: root), screen: 1, library: try SyntheticGames(games),
                           log: RecordingLog(), screenSize: { screen }, scale: { scale }, clock: { clock.now },
                           generator: SeededGenerator(seed: 5))
    }

    /// Plays a screen for a while, ten ticks a second, and adds up what each phase did.
    static func measure(screen: CGSize, scale: CGFloat, seconds: Double) async throws -> Load {
        let clock = TestClock(1000)
        let player = try makePlayer(screen: screen, scale: scale, clock: clock)
        player.start()
        await settle(player)
        var load = Load()
        var gameStart: Double?
        var identity: String?
        let end = clock.now + seconds
        while clock.now < end {
            clock.now += 0.1
            let (scene, drawn) = (player.scene.stats, player.stats)
            player.tick()
            if player.currentGame?.identity != identity {
                identity = player.currentGame?.identity
                gameStart = clock.now
            }
            await settle(player)
            var phase = Phase.other
            if let timeline = player.currentTimeline, let gameStart {
                let time = clock.now - gameStart
                let last = timeline.time(ofMove: max(1, timeline.moveCount))
                if time >= timeline.opening.firstMove, time < last + Look.screensaverMoveInterval {
                    phase = .moves
                } else if time >= last + 1, time < timeline.fadeOutStart {
                    phase = .holding
                }
            }
            load.add(phase, seconds: 0.1, scene: player.scene.stats - scene, player: player.stats - drawn)
            load.movesShown += player.scene.stats.moveFades - scene.moveFades
            if let layout = player.currentLayout {
                let side = Int((layout.board.width * scale).rounded())
                load.boardPixels = side * side
            }
        }
        player.stop()
        return load
    }

    static func describe(_ load: Load, screen: CGSize, scale: CGFloat) -> String {
        func rate(_ value: Int, _ seconds: Double) -> String { String(format: "%.2f", Double(value) / seconds) }
        var lines = ["Screen \(Int(screen.width))x\(Int(screen.height))@\(Int(scale))x, board \(load.boardPixels) pixels"
            + " (\(String(format: "%.1f", Double(load.boardPixels * 4) / 1e6)) MB); \(load.movesShown) moves shown"]
        for phase in Phase.allCases {
            let seconds = load.seconds[phase] ?? 0
            guard seconds > 0 else { continue }
            let scene = load.scene[phase] ?? .init()
            let drawn = load.player[phase] ?? .init()
            let animated = Double(scene.moveFadePixels) * Look.screensaverMoveFade / seconds / Double(max(1, load.boardPixels))
            lines.append("  \(phase.rawValue), \(String(format: "%.1f", seconds)) s: commits \(rate(scene.commits, seconds))/s, "
                + "uploads \(String(format: "%.2f", Double(scene.uploadedPixels) * 4 / 1e6 / seconds)) MB/s, "
                + "move fades \(rate(scene.moveFades, seconds))/s animating \(String(format: "%.4f", animated)) of the board "
                + "on average, board draws \(rate(drawn.boardDraws, seconds))/s covering "
                + "\(String(format: "%.2f", Double(drawn.drawnPixels) / 1e6 / seconds)) Mpx/s")
        }
        if let moves = load.scene[.moves], moves.moveFades > 0 {
            let per = Double(moves.moveFades)
            lines.append("  per move: \(String(format: "%.2f", Double(moves.commits) / per)) commits, "
                + "\(String(format: "%.1f", Double(moves.uploadedPixels) * 4 / 1024 / per)) KB uploaded, "
                + "\(String(format: "%.2f", 100 * Double(moves.moveFadePixels) / per / Double(max(1, load.boardPixels))))% "
                + "of the board fading, \(String(format: "%.1f", Double((load.player[.moves] ?? .init()).drawnPixels) / per / 1e3)) "
                + "kpx drawn")
        }
        return lines.joined(separator: "\n")
    }

    static func report(_ text: String) {
        print(text)
        guard let reportFile else { return }
        let url = URL(fileURLWithPath: reportFile)
        let data = Data((text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    @Test(arguments: [CGSize(width: 1728, height: 1117), CGSize(width: 2560, height: 1440)])
    func aScreensLoad(screen: CGSize) async throws {
        let scale: CGFloat = 2
        let load = try await Self.measure(screen: screen, scale: scale, seconds: 90)
        Self.report(Self.describe(load, screen: screen, scale: scale))
        #expect(load.movesShown >= 90, "two games' moves")
        #expect((load.seconds[.holding] ?? 0) > 15)

        // Holding, nothing is committed, uploaded, or drawn.
        let holding = try #require(load.scene[.holding])
        #expect(holding.commits == 0 && holding.uploadedPixels == 0 && holding.moveFades == 0)
        #expect(load.player[.holding]?.boardDraws == 0)
    }

    // MARK: - Rendering offscreen

    /// What an offscreen renderer did over some frames.
    struct Frames {
        var count = 0
        var damagedPixels = 0.0
        var milliseconds = 0.0

        var describe: String {
            String(format: "%d frames: %.2f Mpx damaged and %.2f ms a frame", count,
                   damagedPixels / 1e6 / Double(max(1, count)), milliseconds / Double(max(1, count)))
        }
    }

    /// Renders a layer tree with a `CARenderer` into a Metal texture of the screen's pixels.
    final class Probe {
        let renderer: CARenderer
        let queue: any MTLCommandQueue

        init?(root: CALayer, screen: CGSize, scale: CGFloat) {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            let width = Int(screen.width * scale), height = Int(screen.height * scale)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height,
                                                                      mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            let host = CALayer()
            host.anchorPoint = .zero
            host.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            host.sublayerTransform = CATransform3DMakeScale(scale, scale, 1)
            host.addSublayer(root)
            renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
            renderer.layer = host
            renderer.bounds = host.bounds
            self.queue = queue
        }

        /// Renders frames at 60 a second from a media time.
        func render(from start: Double, count: Int, into frames: inout Frames) {
            for frame in 0 ..< count {
                let clock = ContinuousClock.now
                renderer.beginFrame(atTime: start + Double(frame) / 60, timeStamp: nil)
                let damage = renderer.updateBounds()
                if !damage.isEmpty, !damage.isInfinite {
                    renderer.addUpdate(damage)
                    frames.damagedPixels += damage.width * damage.height
                }
                renderer.render()
                renderer.endFrame()
                if let buffer = queue.makeCommandBuffer() {
                    buffer.commit()
                    buffer.waitUntilCompleted()
                }
                frames.milliseconds += (ContinuousClock.now - clock) / .milliseconds(1)
                frames.count += 1
            }
        }
    }

    /// Plays twelve moves on a screen, rendering the 24 frames after each, then holds and fades
    /// out. Real time passes between the moves, so that each move's fades have ended before the
    /// next.
    @Test func renderedOffscreen() async throws {
        let screen = CGSize(width: 1728, height: 1117), scale: CGFloat = 2
        let clock = TestClock(1000)
        let player = try Self.makePlayer(screen: screen, scale: scale, clock: clock)
        guard let probe = Probe(root: player.scene.rootLayer, screen: screen, scale: scale) else {
            Self.report("No Metal device, so no offscreen rendering")
            return
        }
        player.start()
        await Self.settle(player)
        clock.now += Look.screensaverStartDelay
        player.tick()
        await Self.settle(player)
        let start = clock.now
        let timeline = try #require(player.currentTimeline)
        var ignored = Frames()
        probe.render(from: CACurrentMediaTime(), count: 1, into: &ignored)

        // Up to the first move, then twelve moves.
        clock.now = start + timeline.opening.firstMove - 0.1
        player.tick()
        await Self.settle(player)
        try await Task.sleep(for: .milliseconds(1100))
        probe.render(from: CACurrentMediaTime(), count: 1, into: &ignored)
        var moves = Frames()
        for _ in 0 ..< 12 {
            clock.now += Look.screensaverMoveInterval
            player.tick()
            await Self.settle(player)
            probe.render(from: CACurrentMediaTime(), count: 24, into: &moves)
            try await Task.sleep(for: .milliseconds(450))
        }

        // Holding after the last move, then the fade-out.
        var hold = Frames()
        var fadeOut = Frames()
        while clock.now < start + timeline.fadeOutStart - 1 {
            clock.now += 0.1
            player.tick()
            await Self.settle(player)
        }
        try await Task.sleep(for: .milliseconds(450))
        clock.now += 0.1
        player.tick()
        await Self.settle(player)
        probe.render(from: CACurrentMediaTime(), count: 1, into: &ignored)
        probe.render(from: CACurrentMediaTime() + 0.02, count: 30, into: &hold)
        clock.now = start + timeline.fadeOutStart + 0.01
        player.tick()
        await Self.settle(player)
        probe.render(from: CACurrentMediaTime(), count: 30, into: &fadeOut)
        player.stop()

        Self.report("""
            Offscreen, 1728x1117@2x, 60 frames a second:
              the 0.4 s after each move, \(moves.describe)
              holding, \(hold.describe)
              fading out, \(fadeOut.describe)
            """)
        #expect(hold.damagedPixels == 0, "holding damages nothing")
    }
}

extension SaverScene.Stats {
    static func + (lhs: Self, rhs: Self) -> Self {
        var sum = lhs
        sum.commits += rhs.commits
        sum.uploadedPixels += rhs.uploadedPixels
        sum.moveFades += rhs.moveFades
        sum.moveFadePixels += rhs.moveFadePixels
        sum.gameFades += rhs.gameFades
        return sum
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        var difference = lhs
        difference.commits -= rhs.commits
        difference.uploadedPixels -= rhs.uploadedPixels
        difference.moveFades -= rhs.moveFades
        difference.moveFadePixels -= rhs.moveFadePixels
        difference.gameFades -= rhs.gameFades
        return difference
    }
}

extension SaverPlayer.Stats {
    static func + (lhs: Self, rhs: Self) -> Self {
        Self(boardDraws: lhs.boardDraws + rhs.boardDraws, drawnPixels: lhs.drawnPixels + rhs.drawnPixels)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(boardDraws: lhs.boardDraws - rhs.boardDraws, drawnPixels: lhs.drawnPixels - rhs.drawnPixels)
    }
}
