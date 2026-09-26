import CoreGraphics
import Foundation
import QuartzCore
import Testing

/// Plays games on a screen's scene without a window, with a clock the test moves, and checks
/// what the player does as the games go by.
@Suite("Screensaver: playing a screen's games")
@MainActor
struct ScreensaverPlayerTests {
    let clock = TestClock(1000)
    let log = RecordingLog()
    let folder: TemporaryFolder
    let library: GameLibrary

    init() throws {
        folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        try writePlaylist(3, to: url)
        library = GameLibrary(playlist: PlaylistStore(url: url, log: log), direct: nil, ownGame: ownGame, log: log,
                              generator: SeededGenerator(seed: 8))
    }

    func player(screen: Int = 1, size: CGSize = CGSize(width: 1920, height: 1080)) -> SaverPlayer {
        let root = CALayer()
        root.anchorPoint = .zero
        root.bounds = CGRect(origin: .zero, size: size)
        let clock = clock
        return SaverPlayer(scene: SaverScene(rootLayer: root), screen: screen, library: library, log: log,
                           screenSize: { size }, scale: { 1 }, clock: { clock.now },
                           generator: SeededGenerator(seed: UInt64(screen)))
    }

    /// Lets the library and the drawing finish what they're doing, ticking the player, until a
    /// condition holds.
    func settle(_ player: SaverPlayer, until condition: () -> Bool) async {
        for _ in 0 ..< 400 where !condition() {
            player.tick()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func playsGamesOneAfterAnother() async throws {
        let player = player()
        player.start()
        await settle(player) { player.nextGame.hasFirstBoard }
        #expect(player.nextGame == (true, true), "nothing plays yet, so the first board is drawn at once")
        player.tick()
        #expect(player.currentGame == nil, "the start delay hasn't passed")

        clock.now += Look.screensaverStartDelay
        player.tick()
        let start = clock.now
        let first = try #require(player.currentGame)
        #expect(first.moveCount == 30)
        let timeline = try #require(player.currentTimeline)
        #expect(timeline.opening == .start, "the first game comes in quickly")
        #expect(timeline.extraHold > 0 && timeline.extraHold <= Look.screensaverMaximumStagger)
        await settle(player) { player.nextGame.isReady }
        #expect(player.nextGame == (true, false), "the next game's board waits for the last move")

        // Through the game, a quarter of a second at a time: the moves come in order, and the
        // screen never holds more than two boards.
        var seen: [Int] = []
        while player.currentGame?.identity == first.identity {
            clock.now += 0.25
            player.tick()
            let wanted = timeline.state(at: clock.now - start).movesShown
            await settle(player) { player.shownMoves == wanted || player.currentGame?.identity != first.identity }
            if player.currentGame?.identity == first.identity {
                #expect(player.shownMoves == wanted)
                if seen.last != player.shownMoves { seen.append(player.shownMoves) }
                #expect(player.boardCount <= 2)
                let bothBoards = player.boardCount + (player.nextGame.hasFirstBoard ? 1 : 0)
                #expect(bothBoards <= 2, "at move \(player.shownMoves)")
                if player.shownMoves == 30 {
                    await settle(player) { player.nextGame.hasFirstBoard }
                    #expect(player.nextGame.hasFirstBoard)
                }
            }
            #expect(clock.now < start + timeline.duration + 0.5, "the game ends on time")
        }
        #expect(seen == Array(0 ... 30))
        let second = try #require(player.currentGame)
        #expect(second.identity != first.identity)
        #expect(player.currentTimeline == SaverTimeline(moveCount: second.moveCount), "the next game comes in as usual")
        #expect(log.messages(.play, level: .notice).count { $0.contains("played a game from the playlist, 19x19, 30 moves") } == 1)

        player.stop()
        #expect(player.currentGame == nil && player.boardCount == 0 && !player.nextGame.isReady)
        #expect(library.games(on: 1).isEmpty, "stopping gives the games back")
    }

    @Test func eachScreenPlaysAGameOfItsOwn() async throws {
        let one = player(screen: 1)
        let two = player(screen: 2, size: CGSize(width: 1080, height: 1920))
        let preview = player(screen: 3, size: CGSize(width: 300, height: 190))
        for player in [one, two, preview] { player.start() }
        clock.now += Look.screensaverStartDelay
        for player in [one, two, preview] {
            await settle(player) { player.currentGame != nil }
        }
        let games = [one, two, preview].compactMap(\.currentGame?.identity)
        #expect(Set(games).count == 3)
        let holds = [one, two, preview].compactMap(\.currentTimeline?.extraHold)
        #expect(Set(holds).count == 3, "the screens start together, and fade out apart")
        for player in [one, two, preview] { player.stop() }
        #expect([1, 2, 3].allSatisfy { library.games(on: $0).isEmpty })
    }

    @Test func everyStartBeginsWithAQuickGame() async throws {
        let player = player()
        for _ in 0 ..< 2 {
            player.start()
            clock.now += Look.screensaverStartDelay
            await settle(player) { player.currentGame != nil }
            let timeline = try #require(player.currentTimeline)
            #expect(timeline.opening == .start)
            #expect(timeline.gameOpacity(at: Look.screensaverStartFadeIn) == 1, "the board is in after a second")
            player.stop()
        }
    }

    @Test func stoppingDropsWorkUnderWay() async throws {
        let player = player()
        player.start()
        player.stop()
        clock.now += 10
        try await Task.sleep(for: .milliseconds(100))
        player.tick()
        #expect(player.currentGame == nil && !player.nextGame.isReady)
        #expect(library.games(on: 1).isEmpty, "a game picked for a stopped screen is given back")
    }
}
