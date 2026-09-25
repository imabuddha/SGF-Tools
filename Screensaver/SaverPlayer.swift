import CoreGraphics
import Foundation
import QuartzCore

/// Plays one screen's games, one after another, on its scene (see `docs/screensaver.md`,
/// sections 3 and 4). The view starts and stops it, and calls ``tick()`` ten times a second.
///
/// Each game comes from the ``GameLibrary`` and is prepared off the main thread while the one
/// before it plays: its layout, its details, and, once the game before it has reached its last
/// move, its first board. Each move's board is drawn off the main thread, one move ahead, and
/// only the board shown and the next are kept, so a screen holds two boards at a time. The first
/// game starts after a random delay, so that screens don't fade in together.
@MainActor
final class SaverPlayer {
    /// The screen's number in the library: the view's serial number.
    let screen: Int
    let scene: SaverScene

    private let library: GameLibrary
    private let log: any SaverLogging
    private let clock: () -> Double
    private let screenSize: () -> CGSize
    private let scale: () -> CGFloat
    private let describeScreen: () -> String
    private var generator: any RandomNumberGenerator
    private let drawingQueue = DispatchQueue(label: "com.pragmaphilia.SGFTools.Screensaver.drawing", qos: .utility)

    private(set) var isPlaying = false
    /// Bumped whenever the work under way no longer counts: on stopping, and for each new game.
    private var generation = 0
    /// When the next game may start: after a random delay on starting, and at once after a game.
    private var nextStart: Double = 0
    private var current: PreparedGame?
    private var currentStart: Double = 0
    private var appliedState: SaverTimeline.State?
    private var next: PreparedGame?
    private var isRequestingNext = false
    private var isDrawingNextFirstBoard = false
    /// The boards drawn for the current game, by moves: the one shown and the next.
    private var boards: [Int: CGImage] = [:]
    private var boardsDrawing: Set<Int> = []
    private(set) var shownMoves = 0
    private var wantedMoves: Int?
    private var drawTimes: [Double] = []

    /// - Parameters:
    ///   - screenSize: The screen's size in points, when a game is prepared.
    ///   - scale: The screen's backing scale, when a game is prepared.
    ///   - describeScreen: The screen, for the log.
    ///   - clock: Seconds, as `CACurrentMediaTime`; the tests set it.
    init(scene: SaverScene, screen: Int, library: GameLibrary, log: any SaverLogging,
         screenSize: @escaping () -> CGSize, scale: @escaping () -> CGFloat,
         describeScreen: @escaping () -> String = { "" }, clock: @escaping () -> Double = { CACurrentMediaTime() },
         generator: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.scene = scene
        self.screen = screen
        self.library = library
        self.log = log
        self.screenSize = screenSize
        self.scale = scale
        self.describeScreen = describeScreen
        self.clock = clock
        self.generator = generator
    }

    // MARK: - What the tests look at

    /// The game playing, if any.
    var currentGame: SaverGame? { current?.game }

    /// The scale the current game was drawn at.
    var currentScale: CGFloat? { current?.scale }

    /// The number of the current game's boards kept.
    var boardCount: Int { boards.count }

    /// Whether the next game is ready, and whether its first board is drawn.
    var nextGame: (isReady: Bool, hasFirstBoard: Bool) { (next != nil, next?.firstBoard != nil) }

    // MARK: - Starting and stopping

    func start() {
        guard !isPlaying else { return }
        isPlaying = true
        generation += 1
        var wrapped = AnyGenerator(base: generator)
        nextStart = clock() + Double.random(in: 0 ... Look.screensaverMaximumStartDelay, using: &wrapped)
        generator = wrapped.base
        requestNextGame()
    }

    /// Stops the drawing, lets go of the images, and gives the games back, so a screen that the
    /// host forgets costs a few kilobytes and no time.
    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        generation += 1
        scene.clear()
        current = nil
        next = nil
        isRequestingNext = false
        isDrawingNextFirstBoard = false
        appliedState = nil
        boards = [:]
        boardsDrawing = []
        wantedMoves = nil
        library.releaseAll(from: screen)
    }

    /// Shows the moment the clock says: the fades, the move, and the next game once a game is over.
    func tick() {
        guard isPlaying else { return }
        let now = clock()
        if current == nil {
            guard now >= nextStart, let next else { return }
            begin(next, at: now)
        }
        guard let current else { return }
        let time = now - currentStart
        let state = current.timeline.state(at: time)
        if state != appliedState {
            scene.apply(state, at: time, animated: true)
            appliedState = state
            if state.movesShown != shownMoves {
                if boards[state.movesShown] != nil {
                    show(moves: state.movesShown)
                } else {
                    wantedMoves = state.movesShown
                    drawBoard(afterMoves: state.movesShown)
                }
            }
        }
        if state.isOver { finish(at: now) }
    }

    // MARK: - Games

    /// Asks the library for the next game, and prepares it off the main thread.
    private func requestNextGame() {
        guard isPlaying, next == nil, !isRequestingNext else { return }
        isRequestingNext = true
        let (generation, size, scale, queue) = (self.generation, screenSize(), scale(), drawingQueue)
        library.requestGame(for: screen, allowsDirect: !SaverLayout.isPreview(size)) { game in
            guard let game else {
                Task { @MainActor in self.received(nil, identity: nil, generation: generation) }
                return
            }
            queue.async {
                var generator = SystemRandomNumberGenerator()
                let prepared = SaverScene.prepare(game, screen: size, scale: scale, drawingFirstBoard: false,
                                                  using: &generator)
                Task { @MainActor in self.received(prepared, identity: game.identity, generation: generation) }
            }
        }
    }

    private func received(_ prepared: PreparedGame?, identity: String?, generation: Int) {
        guard generation == self.generation, isPlaying else {
            if let identity { library.release(identity, from: screen) }
            return
        }
        isRequestingNext = false
        guard let prepared else {
            if let identity { library.release(identity, from: screen) }
            log.error(.play, "Screen \(screen): no game to play; trying again in 5 s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                MainActor.assumeIsolated { self?.requestNextGame() }
            }
            return
        }
        next = prepared
        drawNextFirstBoardIfDue()
    }

    /// Draws the next game's first board off the main thread, once the current game has reached
    /// its last move, or at once if nothing is playing.
    private func drawNextFirstBoardIfDue() {
        guard let next, next.firstBoard == nil, !isDrawingNextFirstBoard else { return }
        if let current, shownMoves < current.game.moveCount { return }
        isDrawingNextFirstBoard = true
        let generation = generation
        drawingQueue.async {
            var drawn = next
            drawn.drawFirstBoard()
            Task { @MainActor in
                guard generation == self.generation, self.next?.game.identity == drawn.game.identity else { return }
                self.next = drawn
                self.isDrawingNextFirstBoard = false
            }
        }
    }

    private func begin(_ prepared: PreparedGame, at now: Double) {
        generation += 1
        current = prepared
        next = nil
        currentStart = now
        appliedState = nil
        boards = [:]
        boardsDrawing = []
        wantedMoves = nil
        shownMoves = 0
        isDrawingNextFirstBoard = false
        drawTimes = prepared.firstBoardTime.map { [$0] } ?? []
        scene.show(prepared)
        if let first = prepared.firstBoard {
            boards[0] = first
        } else {
            // It arrived late: the board appears while the game fades in.
            wantedMoves = 0
            drawBoard(afterMoves: 0)
        }
        drawBoard(afterMoves: 1)
        requestNextGame()
        let layout = prepared.layout
        let details = layout.details == nil ? (layout.leftOutDetails ? "no room for the details" : "no details")
            : "details \(layout.side.map { "\($0)" } ?? "")"
        log.info(.play, """
            Screen \(screen) (\(describeScreen())): \(prepared.game.source.rawValue), \(prepared.game.boardSize), \
            \(prepared.game.moveCount) moves; board \(Int(layout.board.width)) points, \(details)
            """)
    }

    private func finish(at now: Double) {
        guard let current else { return }
        let times = drawTimes.sorted()
        let median = times.isEmpty ? 0 : times[times.count / 2]
        let side = Int((current.layout.board.width * current.scale).rounded())
        log.notice(.play, """
            Screen \(screen) (\(describeScreen())): played a game from the \(current.game.source.rawValue), \
            \(current.game.boardSize), \(current.game.moveCount) moves; drawing \(String(format: "%.1f", median)) ms \
            median, \(String(format: "%.1f", times.last ?? 0)) ms slowest; board \(side)x\(side) pixels
            """)
        library.release(current.game.identity, from: screen)
        self.current = nil
        scene.clear()
        boards = [:]
        nextStart = now
        tick()
    }

    // MARK: - Boards

    /// Draws a board off the main thread, unless it is drawn or being drawn.
    private func drawBoard(afterMoves moves: Int) {
        guard let current, moves <= current.game.moveCount, boards[moves] == nil, !boardsDrawing.contains(moves) else {
            return
        }
        boardsDrawing.insert(moves)
        let (generation, game, side, scale) = (self.generation, current.game, current.layout.board.width, current.scale)
        drawingQueue.async {
            let start = ContinuousClock.now
            let image = SaverScene.boardImage(of: game, afterMoves: moves, side: side, scale: scale)
            let milliseconds = (ContinuousClock.now - start) / .milliseconds(1)
            Task { @MainActor in self.drawn(image, afterMoves: moves, milliseconds: milliseconds, generation: generation) }
        }
    }

    private func drawn(_ image: CGImage?, afterMoves moves: Int, milliseconds: Double, generation: Int) {
        guard generation == self.generation else { return }
        boardsDrawing.remove(moves)
        drawTimes.append(milliseconds)
        guard let image else { return }
        boards[moves] = image
        if wantedMoves == moves { show(moves: moves) }
    }

    /// Shows the board after a number of moves, keeps it and the next one only, and draws the
    /// next.
    private func show(moves: Int) {
        scene.setBoard(boards[moves], animated: true)
        shownMoves = moves
        wantedMoves = nil
        boards = boards.filter { $0.key >= moves }
        drawBoard(afterMoves: moves + 1)
        drawNextFirstBoardIfDue()
    }
}
