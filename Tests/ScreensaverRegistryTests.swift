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
    final class Clock: @unchecked Sendable {
        var now = 100.0
    }

    let log = RecordingLog()
    let clock = Clock()
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
            facts.started = true
        }
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
        registry.update(older.serial) { $0.started = false }
        registry.update(older.serial) { $0.started = true }
        #expect(!older.playing && newer.playing)
    }

    @Test func willStopPausesEveryViewUntilItStartsAgain() {
        let one = startedView(on: .display(1))
        let two = startedView(on: .display(2))
        let preview = startedView(on: .preview)
        registry.willStop()
        #expect(!one.playing && !two.playing && !preview.playing)
        #expect(one.reasons.last == "willstop")
        registry.update(one.serial) { $0.started = false }
        registry.update(one.serial) { $0.started = true }
        #expect(one.playing && !two.playing)
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
