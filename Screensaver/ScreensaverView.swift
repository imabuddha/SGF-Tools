import AppKit
import QuartzCore
import ScreenSaver

/// The SGF Tools screensaver: on each screen, the first 50 moves of a random game, one a second,
/// with its details beside the board (see `docs/screensaver.md`).
///
/// The view handles its life in the host, and its timer. Its ``SaverPlayer`` plays the games,
/// which come from the process's ``GameLibrary``, on its screen's scene. Whether it plays at all
/// comes from the ``InstanceRegistry``, since the host makes more views than it shows and frees
/// few of them.
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
    /// Plays the games, while the registry lets this view play.
    private var player: SaverPlayer?
    /// Ticks the player ten times a second while it plays.
    private var timer: DispatchSourceTimer?
    private var windowObservers: [any NSObjectProtocol] = []

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
        player?.stop()
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
        registry.animationStarted(serial)
    }

    override func stopAnimation() {
        super.stopAnimation()
        Self.log.notice(.lifecycle, "View \(serial): stopAnimation")
        registry.animationStopped(serial)
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
        for delay in [InstanceRegistry.previewStartFallbackDelay, InstanceRegistry.startFallbackDelay] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.registry.checkStartFallback(self.serial)
                }
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
        guard let scale = player?.currentScale, scale != backingScale else { return }
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
    /// has no window or no screen, so that a view the host makes and never shows competes with
    /// none.
    private var key: InstanceRegistry.Key? {
        guard window != nil else { return nil }
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
        guard timer == nil, let layer else { return }
        if player == nil {
            player = SaverPlayer(
                scene: SaverScene(rootLayer: layer), screen: serial, library: Self.library, log: Self.log,
                screenSize: { [weak self] in self?.bounds.size ?? .zero },
                scale: { [weak self] in self?.backingScale ?? 2 },
                describeScreen: { [weak self] in self?.describeScreen() ?? "" }
            )
        }
        player?.start()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.player?.tick() }
        }
        timer.resume()
        self.timer = timer
    }

    /// Stops the timer, and the player, which lets go of its images and gives its games back.
    private func stopPlaying() {
        timer?.cancel()
        timer = nil
        player?.stop()
    }

    private func restartGames(because reason: String) {
        guard timer != nil else { return }
        Self.log.notice(.lifecycle, "View \(serial): new game, since \(reason)")
        stopPlaying()
        startPlaying()
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
                    if name == "didstart" { InstanceRegistry.shared.didStart() }
                }
            }
        }
    }
}
