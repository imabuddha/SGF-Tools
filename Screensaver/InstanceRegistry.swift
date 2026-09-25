import CoreGraphics
import Foundation
import QuartzCore

/// A screensaver view, as the registry sees it.
@MainActor
protocol SaverInstance: AnyObject {
    /// The view's serial number: later views have larger ones.
    var serial: Int { get }

    /// Starts or stops the view's playing, for a reason to log.
    func registry(setPlaying playing: Bool, reason: String)
}

/// Decides which screensaver views may play (see `docs/screensaver.md`, section 8).
///
/// The host makes a new view each time the screensaver starts and doesn't free the old ones,
/// which keep running; it shows two views while the picker is open; it calls `stopAnimation`
/// only for the preview; and `com.apple.screensaver.willstop` is the sign that the screensaver
/// is ending, though it's sometimes missed. So a view plays only while:
/// - `startAnimation` has been called and `stopAnimation` hasn't since, or it has been in a
///   window for 5 seconds without `startAnimation`, so that a host that never calls it doesn't
///   leave the screen black
/// - it has a window and a size that isn't empty
/// - it's the newest live view for its key: its display, or the preview; a view with no screen
///   yet waits
/// - no `willstop` has arrived since it last started
/// - its window isn't occluded. Occlusion is trusted only after the window has once reported
///   itself visible, so a host that misreports it can't keep the screensaver black.
///
/// The views report each change, and the registry checks the rule again for all of them.
@MainActor
final class InstanceRegistry {
    /// Which views compete: those on one display, or the previews.
    enum Key: Hashable, Sendable, CustomStringConvertible {
        case display(CGDirectDisplayID)
        case preview

        var description: String {
            switch self {
            case .display(let id): "display \(id)"
            case .preview: "the preview"
            }
        }
    }

    /// What a view has reported.
    struct Facts: Equatable, Sendable {
        /// `startAnimation` has been called, and `stopAnimation` hasn't since.
        var started = false
        /// When the view got its window, by the registry's clock, or `nil` if it has none.
        var windowSince: Double?
        /// The view has been in a window for 5 seconds without `startAnimation`.
        var startedByFallback = false
        var hasSize = false
        var key: Key?
        /// A `willstop` has arrived since the view last started.
        var stoppedByWillStop = false
        /// What the window last reported: visible, occluded, or nothing yet.
        var isVisible: Bool?
        /// The window has reported itself visible at least once.
        var hasBeenVisible = false

        var hasWindow: Bool { windowSince != nil }
    }

    /// How long a view waits in a window for `startAnimation` before playing anyway, in seconds.
    static let startFallbackDelay: Double = 5

    static let shared = InstanceRegistry(log: SaverLog.shared)

    private struct Entry {
        weak var instance: (any SaverInstance)?
        var facts = Facts()
        var playing = false
    }

    private var entries: [Int: Entry] = [:]
    private var lastSerial = 0
    private let log: any SaverLogging
    private let clock: () -> Double

    init(log: any SaverLogging, clock: @escaping () -> Double = { CACurrentMediaTime() }) {
        self.log = log
        self.clock = clock
    }

    /// A serial number for a new view.
    func makeSerial() -> Int {
        lastSerial += 1
        return lastSerial
    }

    /// The number of views registered and not yet freed.
    var liveCount: Int { entries.values.count { $0.instance != nil } }

    /// Whether a view is playing.
    func isPlaying(_ serial: Int) -> Bool { entries[serial]?.playing ?? false }

    /// What a view has reported.
    func facts(of serial: Int) -> Facts? { entries[serial]?.facts }

    /// Registers a new view.
    func add(_ instance: any SaverInstance) {
        entries[instance.serial] = Entry(instance: instance)
        reevaluate()
    }

    /// Records what a view reports, and checks the rule for every view.
    func update(_ serial: Int, _ change: (inout Facts) -> Void) {
        guard var entry = entries[serial] else { return }
        let before = entry.facts
        change(&entry.facts)
        if entry.facts.started, !before.started { entry.facts.stoppedByWillStop = false }
        if entry.facts.windowSince != before.windowSince, entry.facts.hasWindow { entry.facts.stoppedByWillStop = false }
        if !entry.facts.hasWindow { entry.facts.startedByFallback = false }
        if entry.facts.isVisible == true { entry.facts.hasBeenVisible = true }
        entries[serial] = entry
        reevaluate()
    }

    /// Plays a view that has been in a window for ``startFallbackDelay`` seconds without
    /// `startAnimation`. Views call this that long after they get a window.
    func checkStartFallback(_ serial: Int) {
        guard let facts = entries[serial]?.facts, !facts.started, !facts.startedByFallback,
              let since = facts.windowSince, clock() - since >= Self.startFallbackDelay - 0.01
        else { return }
        log.notice(.lifecycle, "View \(serial): \(Int(Self.startFallbackDelay)) s in a window without startAnimation; playing anyway")
        update(serial) { $0.startedByFallback = true }
    }

    /// `com.apple.screensaver.willstop` arrived: every view stops until it starts again.
    func willStop() {
        for serial in entries.keys { entries[serial]?.facts.stoppedByWillStop = true }
        reevaluate()
    }

    /// A view has been freed.
    func remove(_ serial: Int) {
        entries[serial] = nil
        reevaluate()
    }

    /// Whether a view may play, and why.
    func decision(for serial: Int) -> (play: Bool, reason: String) {
        guard let facts = entries[serial]?.facts else { return (false, "not registered") }
        guard facts.started || facts.startedByFallback else { return (false, "not started") }
        guard !facts.stoppedByWillStop else { return (false, "willstop") }
        guard facts.hasWindow else { return (false, "no window") }
        guard facts.hasSize else { return (false, "empty size") }
        guard let key = facts.key else { return (false, "no screen yet") }
        let newest = entries.filter { $0.value.instance != nil && $0.value.facts.key == key }.keys.max() ?? serial
        guard newest == serial else { return (false, "view \(newest) is newer on \(key)") }
        guard !(facts.hasBeenVisible && facts.isVisible == false) else { return (false, "occluded") }
        return (true, "the newest view on \(key)")
    }

    /// Checks the rule for every view, and tells those whose answer changed.
    private func reevaluate() {
        entries = entries.filter { $0.value.instance != nil }
        for serial in entries.keys.sorted() {
            guard let entry = entries[serial], let instance = entry.instance else { continue }
            let (play, reason) = decision(for: serial)
            guard play != entry.playing else { continue }
            entries[serial]?.playing = play
            log.notice(.lifecycle, "View \(serial) \(play ? "plays" : "pauses"): \(reason); \(liveCount) live views")
            instance.registry(setPlaying: play, reason: reason)
        }
    }
}
