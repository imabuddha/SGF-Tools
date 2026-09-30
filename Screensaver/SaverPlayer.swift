import CoreGraphics
import Foundation
import QuartzCore

/// Plays one screen's games, one after another, on its scene (see `docs/screensaver.md`,
/// sections 3 and 4). The view starts and stops it, and calls ``tick()`` ten times a second.
///
/// Each game comes from a ``SaverGameSource``, the process's ``GameLibrary``, and is prepared off
/// the main thread while the one before it plays: its layout, its details, and, once the game
/// before it has reached its last move, its first board, drawn in full on the game's
/// ``BoardCanvas``. Each move is drawn off the main thread, one move ahead, on that canvas, only
/// where it changes the board, and the scene fades in only the tiles it changed. Once the last
/// move has faded in, the whole last position replaces the tiles, and the canvas goes. So a
/// screen holds two boards at a time: the board layer's image and the canvas, or the last
/// position and the next game's first board. The first game after starting comes in quickly,
/// after a short black, and holds its last position a random time longer, so that screens that
/// start together don't fade out and in together.
@MainActor
final class SaverPlayer {
    /// The screen's number in the library: the view's serial number.
    let screen: Int
    let scene: SaverScene

    private let library: any SaverGameSource
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
    /// When the next game may start: shortly after starting, and at once after a game.
    private var nextStart: Double = 0
    /// Whether the next game is the first since starting, which comes in quicker.
    private var nextIsFirst = false
    /// How much longer the first game since starting holds its last position, in seconds.
    private var firstExtraHold: Double = 0
    private var current: PreparedGame?
    private var currentStart: Double = 0
    private var appliedState: SaverTimeline.State?
    private var next: PreparedGame?
    private var isRequestingNext = false
    private var isDrawingNextFirstBoard = false

    /// A change of the board, from the moves shown to the moves wanted.
    private struct Step: Hashable {
        let from: Int
        let to: Int
    }

    /// The current game's canvas, used only on the drawing queue: from its first board until
    /// its last position is whole in the board layer.
    private var canvas: BoardCanvas?
    private var isMakingCanvas = false
    /// The moves drawn ahead, by step. Only those from the moves shown count.
    private var updates: [Step: BoardUpdate] = [:]
    private var stepsDrawing: Set<Step> = []
    private(set) var shownMoves = 0
    private var wantedMoves: Int?
    /// When the moves shown last changed, by the clock.
    private var shownAt: Double = 0
    /// The last position as one image, once made, until it replaces the tiles.
    private var lastBoard: CGImage?
    private var isMakingLastBoard = false
    /// Whether the board layer holds the last position whole, with no tiles over it.
    private(set) var isBoardWhole = false
    private var drawTimes: [Double] = []

    /// What the player has drawn, for the tests that measure the load (see ``SaverScene/Stats``).
    struct Stats: Sendable, Equatable {
        /// The moves drawn, whole or in part (not the first boards).
        var boardDraws = 0
        /// The pixels those draws covered.
        var drawnPixels = 0
    }

    private(set) var stats = Stats()

    /// - Parameters:
    ///   - screenSize: The screen's size in points, when a game is prepared.
    ///   - scale: The screen's backing scale, when a game is prepared.
    ///   - describeScreen: The screen, for the log.
    ///   - clock: Seconds, as `CACurrentMediaTime`; the tests set it.
    ///   - generator: Chooses how much longer the first game holds its last position, and nothing
    ///     else: each game's layout is chosen on the drawing queue with the system's generator, so
    ///     a seed doesn't repeat the layouts.
    init(scene: SaverScene, screen: Int, library: any SaverGameSource, log: any SaverLogging,
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

    /// The current game's timeline.
    var currentTimeline: SaverTimeline? { current?.timeline }

    /// The current game's layout.
    var currentLayout: SaverLayout? { current?.layout }

    /// Whether drawing or picking is under way, which the tests wait for.
    var hasWorkUnderWay: Bool {
        !stepsDrawing.isEmpty || isRequestingNext || isDrawingNextFirstBoard || isMakingCanvas || isMakingLastBoard
    }

    /// The number of whole boards the current game keeps, at most: the board layer's image, and
    /// the canvas until the last position replaces that image.
    var boardCount: Int {
        guard current != nil else { return 0 }
        return 1 + (canvas != nil ? 1 : 0)
    }

    /// Whether the next game is ready, and whether its first board is drawn.
    var nextGame: (isReady: Bool, hasFirstBoard: Bool) { (next != nil, next?.firstBoard != nil) }

    // MARK: - Starting and stopping

    func start() {
        guard !isPlaying else { return }
        isPlaying = true
        generation += 1
        var wrapped = AnyGenerator(base: generator)
        firstExtraHold = Double.random(in: 0 ... Look.screensaverMaximumStagger, using: &wrapped)
        generator = wrapped.base
        nextStart = clock() + Look.screensaverStartDelay
        nextIsFirst = true
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
        forgetBoards()
        library.releaseAll(from: screen)
    }

    /// Shows the moment the clock says: the fades, the move, and the next game once a game is
    /// over. A tick where nothing changes asks nothing of the scene.
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
            var update: BoardUpdate?
            if state.movesShown != shownMoves {
                let step = Step(from: shownMoves, to: state.movesShown)
                if let ready = updates[step] {
                    update = ready
                } else {
                    wantedMoves = state.movesShown
                    drawBoard(step)
                }
            }
            scene.apply(state, at: time, animated: true, board: update)
            appliedState = state
            if let update { didShow(update, at: now) }
        }
        makeBoardWholeIfDue(at: now)
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

    /// Draws the next game's first board off the main thread, once the current game's last
    /// position is whole in the board layer, or at once if nothing is playing.
    private func drawNextFirstBoardIfDue() {
        guard let next, next.firstBoard == nil, !isDrawingNextFirstBoard else { return }
        if current != nil, !isBoardWhole { return }
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
        var prepared = prepared
        if nextIsFirst {
            prepared.timeline = SaverTimeline(moveCount: prepared.timeline.moveCount, opening: .start, extraHold: firstExtraHold)
            nextIsFirst = false
        }
        generation += 1
        forgetBoards()
        canvas = prepared.canvas
        // The player keeps the canvas, so that it can let it go before the game ends.
        prepared.canvas = nil
        current = prepared
        next = nil
        currentStart = now
        appliedState = nil
        shownAt = now
        isDrawingNextFirstBoard = false
        drawTimes = prepared.firstBoardTime.map { [$0] } ?? []
        scene.show(prepared)
        if canvas != nil {
            boardIsReady()
        } else {
            // It arrived late: the board appears while the game fades in.
            makeCanvas()
        }
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
        let side = current.boardPixels
        log.notice(.play, """
            Screen \(screen) (\(describeScreen())): played a game from \(current.game.source), \
            \(current.game.boardSize), \(current.game.moveCount) moves; drawing \(String(format: "%.1f", median)) ms \
            median, \(String(format: "%.1f", times.last ?? 0)) ms slowest; board \(side)x\(side) pixels
            """)
        library.release(current.game.identity, from: screen)
        generation += 1
        self.current = nil
        scene.clear()
        forgetBoards()
        nextStart = now
        tick()
    }

    // MARK: - Boards

    private func forgetBoards() {
        canvas = nil
        isMakingCanvas = false
        updates = [:]
        stepsDrawing = []
        wantedMoves = nil
        shownMoves = 0
        lastBoard = nil
        isMakingLastBoard = false
        isBoardWhole = false
    }

    /// Makes the current game's canvas and first board off the main thread, when the game
    /// begins before they're drawn.
    private func makeCanvas() {
        guard let current, !isMakingCanvas else { return }
        isMakingCanvas = true
        let generation = generation
        drawingQueue.async {
            var prepared = current
            prepared.drawFirstBoard()
            let (canvas, image, milliseconds) = (prepared.canvas, prepared.firstBoard, prepared.firstBoardTime)
            Task { @MainActor in
                guard generation == self.generation else { return }
                self.isMakingCanvas = false
                if let milliseconds { self.drawTimes.append(milliseconds) }
                guard let canvas else { return }
                self.canvas = canvas
                self.scene.setBoard(image)
                self.boardIsReady()
            }
        }
    }

    /// The first board is on the scene and the canvas is ready: draws the next move, or the move
    /// the clock has reached if the board came late.
    private func boardIsReady() {
        guard let current else { return }
        if current.game.moveCount == 0 {
            makeBoardWhole(nil)
        } else {
            drawBoard(Step(from: 0, to: wantedMoves ?? 1))
        }
    }

    /// Draws a step on the canvas off the main thread, unless it is drawn or being drawn.
    private func drawBoard(_ step: Step) {
        guard let current, let canvas, step.to <= current.game.moveCount, updates[step] == nil,
              !stepsDrawing.contains(step)
        else { return }
        stepsDrawing.insert(step)
        let generation = generation
        drawingQueue.async {
            let update = canvas.update(from: step.from, to: step.to)
            Task { @MainActor in self.drawn(update, generation: generation) }
        }
    }

    private func drawn(_ update: BoardUpdate, generation: Int) {
        guard generation == self.generation else { return }
        let step = Step(from: update.from, to: update.moves)
        stepsDrawing.remove(step)
        drawTimes.append(update.milliseconds)
        stats.boardDraws += 1
        stats.drawnPixels += update.drawnPixels
        // Drawn from moves no longer shown, it's of no use.
        guard update.from == shownMoves else { return }
        updates[step] = update
        if wantedMoves == update.moves {
            scene.showBoard(update, animated: true)
            didShow(update, at: clock())
        }
    }

    /// The scene shows a move: draws the next, or makes the last position whole.
    private func didShow(_ update: BoardUpdate, at now: Double) {
        guard let current else { return }
        shownMoves = update.moves
        shownAt = now
        wantedMoves = nil
        updates = [:]
        if shownMoves < current.game.moveCount {
            drawBoard(Step(from: shownMoves, to: shownMoves + 1))
        } else {
            makeLastBoard()
        }
    }

    /// Makes the last position one image, off the main thread.
    private func makeLastBoard() {
        guard let canvas, lastBoard == nil, !isMakingLastBoard else { return }
        isMakingLastBoard = true
        let (generation, moves) = (generation, shownMoves)
        drawingQueue.async {
            canvas.draw(afterMoves: moves)
            let image = canvas.image()
            Task { @MainActor in
                guard generation == self.generation else { return }
                self.isMakingLastBoard = false
                self.lastBoard = image
            }
        }
    }

    /// Puts the last position in the board layer in place of the tiles, once its move has faded
    /// in and while the game is shown, which looks the same.
    private func makeBoardWholeIfDue(at now: Double) {
        guard !isBoardWhole, let lastBoard, appliedState?.showsGame == true,
              now >= shownAt + Look.screensaverMoveFade + 0.1
        else { return }
        makeBoardWhole(lastBoard)
    }

    /// The board layer holds the last position whole: from `image`, or as it is if `nil`. Lets
    /// go of the canvas, and draws the next game's first board.
    private func makeBoardWhole(_ image: CGImage?) {
        if let image { scene.setBoard(image) }
        isBoardWhole = true
        lastBoard = nil
        canvas = nil
        drawNextFirstBoardIfDue()
    }
}
