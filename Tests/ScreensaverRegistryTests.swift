import Foundation
import Testing

/// A stand-in for a screensaver view, which records what the registry tells it.
@MainActor
final class FakeInstance: SaverInstance {
    let serial: Int
    private(set) var playing = false
    private(set) var reasons: [String] = []

    init(serial: Int) {
        self.serial = serial
    }

    func registry(setPlaying playing: Bool, reason: String) {
        self.playing = playing
        reasons.append(reason)
    }
}

@Suite("Screensaver: which views play")
@MainActor
struct ScreensaverRegistryTests {
    let log = RecordingLog()
    let clock = TestClock(100)
    let registry: InstanceRegistry

    init() {
        let clock = clock
        registry = InstanceRegistry(log: log, clock: { clock.now })
    }

    /// A view that has started, in a window of a size, on a key.
    func startedView(on key: InstanceRegistry.Key?) -> FakeInstance {
        let view = FakeInstance(serial: registry.makeSerial())
        registry.add(view)
        let now = clock.now
        registry.update(view.serial) { facts in
            facts.windowSince = now
            facts.hasSize = true
            facts.key = key
        }
        registry.animationStarted(view.serial)
        return view
    }

    @Test func theNewestViewOnEachDisplayPlays() {
        let first = startedView(on: .display(1))
        #expect(first.playing)
        let second = startedView(on: .display(1))
        #expect(!first.playing && second.playing)
        #expect(first.reasons.last == "view 2 is newer on display 1")
        let other = startedView(on: .display(2))
        #expect(other.playing && second.playing)
        #expect(registry.liveCount == 3)
        #expect(log.messages(.lifecycle).contains("View 1 pauses: view 2 is newer on display 1; 2 live views"))
    }

    @Test func startAnimationOnAnOlderViewIsIgnored() {
        let older = startedView(on: .display(1))
        let newer = startedView(on: .display(1))
        registry.animationStopped(older.serial)
        registry.animationStarted(older.serial)
        #expect(!older.playing && newer.playing)
    }

    @Test func willStopPausesEveryViewUntilItStartsAgain() {
        let one = startedView(on: .display(1))
        let two = startedView(on: .display(2))
        let preview = startedView(on: .preview)
        clock.now += 10
        registry.willStop()
        #expect(!one.playing && !two.playing && !preview.playing)
        #expect(one.reasons.last == "willstop")
        // The host calls startAnimation again, without stopAnimation, as it does for a screen.
        registry.animationStarted(one.serial)
        #expect(one.playing && !two.playing)
        // A new session.
        registry.didStart()
        #expect(two.playing && preview.playing)
    }

    @Test func aWillStopRightAfterStartAnimationIsThePreviousSessions() {
        let older = startedView(on: .display(1))
        clock.now += 60
        let newer = startedView(on: .display(1))
        clock.now += 0.5
        registry.willStop()
        #expect(newer.playing && !older.playing)
        #expect(log.messages(.lifecycle).contains("View 2: willstop ignored, 500 ms after startAnimation"))
        #expect(registry.facts(of: older.serial)?.stoppedByWillStop == true)
        clock.now += 60
        registry.willStop()
        #expect(!newer.playing && newer.reasons.last == "willstop")
        #expect(!older.playing, "the older view doesn't take over")
    }

    @Test func aPreviewIsItsOwnKey() {
        let screen = startedView(on: .display(1))
        let preview = startedView(on: .preview)
        #expect(screen.playing && preview.playing)
        // Two previews while the picker is open: the newer one plays.
        let secondPreview = startedView(on: .preview)
        #expect(!preview.playing && secondPreview.playing && screen.playing)
    }

    @Test func aViewWithoutAScreenWindowOrSizeWaits() {
        let view = startedView(on: nil)
        #expect(!view.playing)
        registry.update(view.serial) { $0.key = .display(3) }
        #expect(view.playing)
        registry.update(view.serial) { $0.hasSize = false }
        #expect(!view.playing && view.reasons.last == "empty size")
        registry.update(view.serial) { $0.hasSize = true }
        registry.update(view.serial) { $0.windowSince = nil }
        #expect(!view.playing && view.reasons.last == "no window")
    }

    @Test func occlusionIsIgnoredUntilTheWindowHasBeenVisible() {
        let view = startedView(on: .display(1))
        registry.update(view.serial) { $0.isVisible = false }
        #expect(view.playing, "an occluded report before any visible one is not trusted")
        registry.update(view.serial) { $0.isVisible = true }
        registry.update(view.serial) { $0.isVisible = false }
        #expect(!view.playing && view.reasons.last == "occluded")
        registry.update(view.serial) { $0.isVisible = true }
        #expect(view.playing)
    }

    @Test func aViewThatNeverGetsStartAnimationPlaysAfterFiveSeconds() {
        let view = FakeInstance(serial: registry.makeSerial())
        registry.add(view)
        let now = clock.now
        registry.update(view.serial) { facts in
            facts.windowSince = now
            facts.hasSize = true
            facts.key = .display(1)
        }
        registry.checkStartFallback(view.serial)
        #expect(!view.playing, "too early")
        clock.now += 5
        registry.checkStartFallback(view.serial)
        #expect(view.playing)
        #expect(log.messages(.lifecycle).contains("View 1: 5 s in a window without startAnimation; playing anyway"))
        // The host's calls win over the fallback.
        registry.animationStopped(view.serial)
        #expect(!view.playing && view.reasons.last == "not started")
    }

    @Test func aViewThatHasStartedAndStoppedWaitsForStartAnimation() {
        let view = FakeInstance(serial: registry.makeSerial())
        registry.add(view)
        let now = clock.now
        registry.update(view.serial) { facts in
            facts.windowSince = now
            facts.hasSize = true
            facts.key = .preview
        }
        registry.animationStarted(view.serial)
        registry.animationStopped(view.serial)
        clock.now += 5
        registry.checkStartFallback(view.serial)
        #expect(!view.playing)
    }

    @Test func aNewerViewThatCannotPlayDoesNotPauseTheOlder() {
        let preview = startedView(on: .preview)
        // Made by the host but not shown: no window or size yet.
        let extra = FakeInstance(serial: registry.makeSerial())
        registry.add(extra)
        registry.update(extra.serial) { $0.key = .preview }
        #expect(preview.playing && !extra.playing)
        let now = clock.now
        registry.update(extra.serial) { facts in
            facts.windowSince = now
            facts.hasSize = true
        }
        #expect(preview.playing, "in a window, but not started")
        registry.animationStarted(extra.serial)
        #expect(!preview.playing && extra.playing)
        #expect(preview.reasons.last == "view 2 is newer on the preview")
    }

    @Test func aFreedViewNoLongerCompetes() {
        var older: FakeInstance? = startedView(on: .display(1))
        let newer = startedView(on: .display(1))
        #expect(newer.playing && older?.playing == false)
        registry.remove(newer.serial)
        #expect(older?.playing == true, "the host freed the newer view")
        older = nil
        #expect(registry.liveCount == 0)
        let latest = startedView(on: .display(1))
        #expect(latest.playing)
    }
}
