import AppKit
import QuartzCore
import ScreenSaver

/// The SGF Tools screensaver: on each screen, the first 50 moves of a random game, one a second,
/// with its details beside the board (see `docs/screensaver.md`).
///
/// The view handles its life in the host, its timer, and its screen's scene. Which games it
/// plays comes from the process's ``GameLibrary``, and whether it plays at all from the
/// ``InstanceRegistry``, since the host makes more views than it shows and frees few of them.
@objc(SGFToolsScreenSaverView)
final class ScreensaverView: ScreenSaverView, SaverInstance {
    /// The games every screen of the process shares, with the own game from this bundle, not
    /// `Bundle.main`, which is the host's.
    private static let library = GameLibrary(bundle: Bundle(for: ScreensaverView.self))

    private static let log: any SaverLogging = SaverLog.shared

    /// Whether the process's first view has logged the loading and started watching the host's
    /// notifications.
    private static var isSetUp = false

    let serial: Int
    private let registry = InstanceRegistry.shared
    private var scene: SaverScene?
    private var isPlaying = false
    private var timer: DispatchSourceTimer?
    private var windowObservers: [any NSObjectProtocol] = []
    private var generator = SystemRandomNumberGenerator()

    /// Bumped whenever the work under way no longer counts: on pausing, and for each new game.
    private var generation = 0
    /// When the next game may start: after a random delay on starting, so screens don't fade
    /// in together, and at once after a game.
    private var nextStart: Double = 0
    private var current: PreparedGame?
    private var currentStart: Double = 0
    private var appliedState: SaverTimeline.State?
    private var next: PreparedGame?
    private var isRequestingNext = false

    /// The boards drawn for the current game, by moves: the one shown and the next.
    private var boards: [Int: CGImage] = [:]
    private var boardsDrawing: Set<Int> = []
    private var shownMoves = 0
    private var wantedMoves: Int?
    private var drawTimes: [Double] = []
    private let drawingQueue = DispatchQueue(label: "com.pragmaphilia.SGFTools.Screensaver.drawing", qos: .utility)

    override init?(frame: NSRect, isPreview: Bool) {
        serial = InstanceRegistry.shared.makeSerial()
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        Self.setUpOnce()
        Self.log.notice(.lifecycle, """
            View \(serial) made: frame \(Self.describe(frame)), isPreview \(isPreview), \
            preview by size \(SaverLayout.isPreview(frame.size)); \(registry.liveCount + 1) live views
            """)
        registry.add(self)
        reportSize()
    }

    required init?(coder: NSCoder) {
        nil
    }

    isolated deinit {
        timer?.cancel()
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        Self.library.releaseAll(from: serial)
        registry.remove(serial)
        Self.log.notice(.lifecycle, "View \(serial) freed; \(registry.liveCount) live views")
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        return layer
    }

    override func draw(_ rect: NSRect) {
        // Black, for the moment before the layers exist.
        NSColor.black.setFill()
        rect.fill()
    }

    override var hasConfigureSheet: Bool { false }

    /// Nothing: the view's own timer drives it, because the host's calls to this are unreliable
    /// in recent releases.
    override func animateOneFrame() {}

    // MARK: - The host's calls

    override func startAnimation() {
        super.startAnimation()
        Self.log.notice(.lifecycle, "View \(serial): startAnimation")
        registry.update(serial) { $0.started = true }
    }

    override func stopAnimation() {
        super.stopAnimation()
        Self.log.notice(.lifecycle, "View \(serial): stopAnimation")
        registry.update(serial) { $0.started = false }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
        let now = CACurrentMediaTime()
        let hasWindow = window != nil
        Self.log.notice(.lifecycle, "View \(serial): \(hasWindow ? "in a window" : "out of its window"); \(describeScreen())")
        registry.update(serial) { [key] facts in
            facts.windowSince = hasWindow ? now : nil
            facts.key = key
            facts.isVisible = nil
            facts.hasBeenVisible = false
        }
        guard let window else { return }
        windowObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        })
        windowObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenChanged() }
        })
        occlusionChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + InstanceRegistry.startFallbackDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.registry.checkStartFallback(self.serial)
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        guard newSize != oldSize else { return }
        Self.log.notice(.lifecycle, "View \(serial): size \(Int(newSize.width))x\(Int(newSize.height))")
        reportSize()
        restartGames(because: "the size changed")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let current, current.scale != backingScale else { return }
        Self.log.notice(.lifecycle, "View \(serial): backing scale \(backingScale)")
        restartGames(because: "the backing scale changed")
    }

    private func occlusionChanged() {
        guard let window else { return }
        let visible = window.occlusionState.contains(.visible)
        Self.log.notice(.lifecycle, "View \(serial): \(visible ? "visible" : "occluded")")
        registry.update(serial) { $0.isVisible = visible }
    }

    private func screenChanged() {
        Self.log.notice(.lifecycle, "View \(serial): screen changed; \(describeScreen())")
        registry.update(serial) { [key] in $0.key = key }
    }

    private func reportSize() {
        registry.update(serial) { [key, bounds] facts in
            facts.hasSize = !bounds.isEmpty
            facts.key = key
        }
    }

    /// The views this one competes with: the previews, or those on its display. `nil` while it
    /// has no screen.
    private var key: InstanceRegistry.Key? {
        if SaverLayout.isPreview(bounds.size) { return .preview }
        return displayID.map { .display($0) }
    }

    private var displayID: CGDirectDisplayID? {
        (window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? window?.screen?.backingScaleFactor ?? 2
    }

    // MARK: - Playing

    func registry(setPlaying playing: Bool, reason: String) {
        if playing { startPlaying() } else { stopPlaying() }
    }

    private func startPlaying() {
        guard !isPlaying else { return }
        isPlaying = true
        generation += 1
        if scene == nil, let layer { scene = SaverScene(rootLayer: layer) }
        nextStart = CACurrentMediaTime() + Double.random(in: 0 ... Look.screensaverMaximumStartDelay, using: &generator)
        requestNextGame()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.resume()
        self.timer = timer
    }

    /// Stops the timer and the drawing, lets go of the images, and gives the games back, so a
    /// view the host forgets costs a few kilobytes and no time.
    private func stopPlaying() {
        guard isPlaying else { return }
        isPlaying = false
        generation += 1
        timer?.cancel()
        timer = nil
        scene?.clear()
        current = nil
        next = nil
        isRequestingNext = false
        appliedState = nil
        boards = [:]
        boardsDrawing = []
        wantedMoves = nil
        Self.library.releaseAll(from: serial)
    }

    private func restartGames(because reason: String) {
        guard isPlaying else { return }
        Self.log.notice(.lifecycle, "View \(serial): new game, since \(reason)")
        stopPlaying()
        startPlaying()
    }

    /// Asks the library for the next game, and prepares it off the main thread.
    private func requestNextGame() {
        guard isPlaying, next == nil, !isRequestingNext else { return }
        isRequestingNext = true
        let (generation, size, scale, serial, queue) = (self.generation, bounds.size, backingScale, serial, drawingQueue)
        Self.library.requestGame(for: serial, allowsDirect: !SaverLayout.isPreview(size)) { game in
            guard let game else {
                Task { @MainActor in self.received(nil, identity: nil, generation: generation) }
                return
            }
            queue.async {
                var generator = SystemRandomNumberGenerator()
                let prepared = SaverScene.prepare(game, screen: size, scale: scale, using: &generator)
                Task { @MainActor in self.received(prepared, identity: game.identity, generation: generation) }
            }
        }
    }

    private func received(_ prepared: PreparedGame?, identity: String?, generation: Int) {
        guard generation == self.generation, isPlaying else {
            if let identity { Self.library.release(identity, from: serial) }
            return
        }
        isRequestingNext = false
        guard let prepared else {
            if let identity { Self.library.release(identity, from: serial) }
            Self.log.error(.play, "View \(serial): no game to play; trying again in 5 s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                MainActor.assumeIsolated { self?.requestNextGame() }
            }
            return
        }
        next = prepared
    }

    private func tick() {
        guard isPlaying else { return }
        let now = CACurrentMediaTime()
        if current == nil {
            guard now >= nextStart, let next else { return }
            begin(next, at: now)
        }
        guard let current else { return }
        let time = now - currentStart
        let state = current.timeline.state(at: time)
        if state != appliedState {
            scene?.apply(state, at: time, animated: true)
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
        drawTimes = [prepared.firstBoardTime]
        if let first = prepared.firstBoard { boards[0] = first }
        scene?.show(prepared)
        drawBoard(afterMoves: 1)
        requestNextGame()
        let layout = prepared.layout
        let details = layout.details == nil ? (layout.leftOutDetails ? "no room for the details" : "no details")
            : "details \(layout.side.map { "\($0)" } ?? "")"
        Self.log.info(.play, """
            Screen \(serial) (\(describeScreen())): \(prepared.game.source.rawValue), \(prepared.game.boardSize), \
            \(prepared.game.moveCount) moves; board \(Int(layout.board.width)) points, \(details)
            """)
    }

    private func finish(at now: Double) {
        guard let current else { return }
        let times = drawTimes.sorted()
        let median = times.isEmpty ? 0 : times[times.count / 2]
        let side = Int((current.layout.board.width * current.scale).rounded())
        Self.log.notice(.play, """
            Screen \(serial) (\(describeScreen())): played a game from the \(current.game.source.rawValue), \
            \(current.game.boardSize), \(current.game.moveCount) moves; drawing \(String(format: "%.1f", median)) ms \
            median, \(String(format: "%.1f", times.last ?? 0)) ms slowest; board \(side)x\(side) pixels
            """)
        Self.library.release(current.game.identity, from: serial)
        self.current = nil
        scene?.clear()
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
        scene?.setBoard(boards[moves], animated: true)
        shownMoves = moves
        wantedMoves = nil
        boards = boards.filter { $0.key >= moves }
        drawBoard(afterMoves: moves + 1)
    }

    // MARK: - Logging

    private func describeScreen() -> String {
        let display = displayID.map { "display \($0)" } ?? "no display"
        return "\(display), frame \(Self.describe(frame)), scale \(backingScale), key \(key.map { "\($0)" } ?? "none")"
    }

    private static func describe(_ rect: NSRect) -> String {
        "\(Int(rect.width))x\(Int(rect.height))"
    }

    /// Logs the loading and the environment, and watches the host's notifications, once per
    /// process.
    private static func setUpOnce() {
        guard !isSetUp else { return }
        isSetUp = true
        let bundle = Bundle(for: ScreensaverView.self)
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let process = ProcessInfo.processInfo
        log.notice(.lifecycle, """
            SGF Tools screensaver \(version) (\(build)) loaded in \(process.processName) \
            (\(process.processIdentifier)) on \(process.operatingSystemVersionString)
            """)
        let home = NSHomeDirectory()
        log.notice(.environment, "The sandbox's home folder is \(home.contains("/Library/Containers/") ? "a container" : "not a container"):",
                   path: home)
        log.notice(.environment, "The real home folder:", path: Playlist.realHomeDirectory.path)

        let center = DistributedNotificationCenter.default()
        for name in ["willstop", "didstart", "didstop", "didlaunch", "previewdidstop"] {
            center.addObserver(forName: Notification.Name("com.apple.screensaver.\(name)"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    log.notice(.lifecycle, "com.apple.screensaver.\(name); \(InstanceRegistry.shared.liveCount) live views")
                    if name == "willstop" { InstanceRegistry.shared.willStop() }
                }
            }
        }
    }
}
