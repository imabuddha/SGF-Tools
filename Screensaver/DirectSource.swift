import Darwin
import Dispatch
import Foundation
import SGFKit
import Synchronization

/// Direct mode: the screensaver asks Spotlight for games and reads the files itself, when there
/// is no playlist (see `docs/screensaver.md`, 1.8). It is never used in a preview.
///
/// Every read is a test of what the host may read. macOS's privacy settings guard almost every
/// place SGF files are, and a read there may be refused, or wait on a permission request that
/// nobody answers, so each read has a time limit, and a location that refuses is left alone:
/// - A location is **denied** after 2 `denied` outcomes, or 3 time-outs in a row, until a late
///   read from it succeeds.
/// - A location is **skipped** after 5 `unreadable` outcomes.
/// - `missing`, `dataless`, and `not a game` just pick again.
/// - Direct mode gives up for the process after 20 failed picks in a row, when 6 abandoned reads
///   haven't come back, after a query that fails or times out, or when every location is denied
///   or skipped.
///
/// `pick` runs on the game library's queue, and blocks while it reads, one read at a time. Reads
/// run on a queue of their own, never the main thread or Swift's cooperative pool, since a read
/// waiting on macOS blocks its thread until macOS answers. So the threads held are one for the
/// read under way and one for each abandoned read that hasn't come back, which the limit on those
/// bounds.
final class DirectSource: @unchecked Sendable {
    /// The limits of 1.8, which the tests shorten.
    struct Limits: Sendable {
        var queryTimeout: Double = 10
        var readTimeout: Double = 3
        var deniedOutcomes = 2
        var timeoutsInARow = 3
        var unreadableOutcomes = 5
        var failedPicksInARow = 20
        /// Abandoned reads that haven't come back yet. Each holds a thread until macOS answers,
        /// and a location is denied after ``timeoutsInARow`` of them, so this is two locations'
        /// worth.
        var blockedReads = 6
        /// A candidate list this old, in seconds, is asked for again when a new session starts.
        var refreshAge: Double = 3600
    }

    /// Whether a location may be read.
    enum Health: Sendable, Equatable {
        case ok
        case denied
        case skipped
    }

    private struct Location {
        var candidates: [String] = []
        var denied = 0
        var timeoutsInARow = 0
        var unreadable = 0
        var health = Health.ok
    }

    /// Everything that a late read, on the read queue, may change too.
    private struct State {
        var locations: [LocationClass: Location] = [:]
        var queriedAt: Double?
        var sessionStarted = false
        var failedPicksInARow = 0
        /// Reads that were abandoned and haven't come back yet.
        var blockedReads = 0
        var givenUp: String?
    }

    private let query: @Sendable () throws -> [String]
    private let reader: GameFileReader
    private let home: URL
    private let volumes: @Sendable () -> [LocationClass]
    private let limits: Limits
    private let log: any SaverLogging
    private let clock: @Sendable () -> Double
    private let state = Mutex(State())
    private let readQueue = DispatchQueue(label: "com.pragmaphilia.SGFTools.Screensaver.reads", qos: .utility,
                                          attributes: .concurrent)
    private let queryQueue = DispatchQueue(label: "com.pragmaphilia.SGFTools.Screensaver.query", qos: .utility)

    /// - Parameters:
    ///   - query: Asks Spotlight for the qualifying paths.
    ///   - reader: Reads a file; the tests replace its system calls.
    ///   - volumes: The mounted volumes, so that each gets a count in the log, even of 0.
    ///   - clock: Seconds, for the candidate list's age.
    init(query: @escaping @Sendable () throws -> [String] = { try GameCandidates.spotlightPaths() },
         reader: GameFileReader = GameFileReader(), home: URL = Playlist.realHomeDirectory,
         volumes: @escaping @Sendable () -> [LocationClass] = { GameCandidates.mountedVolumes() },
         limits: Limits = Limits(), log: any SaverLogging,
         clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.query = query
        self.reader = reader
        self.home = home
        self.volumes = volumes
        self.limits = limits
        self.log = log
        self.clock = clock
    }

    /// Why direct mode gave up for the process, or `nil` if it hasn't.
    var reasonGivenUp: String? { state.withLock { $0.givenUp } }

    /// Whether a location may be read.
    func health(of location: LocationClass) -> Health {
        state.withLock { $0.locations[location]?.health ?? .ok }
    }

    /// A new screensaver session has started: a candidate list an hour old is asked for again at
    /// the next pick.
    func sessionDidStart() {
        state.withLock { $0.sessionStarted = true }
    }

    /// Reads random candidates until one is a game, avoiding the games in the first set it can,
    /// or returns `nil` if direct mode gives up.
    func pick(avoiding avoided: [Set<String>], using generator: inout some RandomNumberGenerator) -> SaverGame? {
        guard reasonGivenUp == nil, loadCandidates() else { return nil }
        while true {
            let open: [LocationClass: Location]? = state.withLock { state in
                if state.givenUp != nil { return nil }
                if state.failedPicksInARow >= limits.failedPicksInARow {
                    giveUp(&state, "\(state.failedPicksInARow) failed picks in a row")
                    return nil
                }
                let open = state.locations.filter { $0.value.health == .ok && !$0.value.candidates.isEmpty }
                guard !open.isEmpty else {
                    giveUp(&state, "every location is denied or skipped")
                    return nil
                }
                return open
            }
            guard let open else { return nil }
            let (path, location) = Self.choose(from: open, avoiding: avoided, using: &generator)
            if let game = read(path, in: location) { return game }
        }
    }

    // MARK: - Candidates

    /// Asks Spotlight for candidates if there are none yet, or if a new session has started and
    /// the list is an hour old. Returns whether there are any.
    private func loadCandidates() -> Bool {
        let due = state.withLock { state in
            guard let queriedAt = state.queriedAt else { return true }
            defer { state.sessionStarted = false }
            return state.sessionStarted && clock() - queriedAt >= limits.refreshAge
        }
        guard due else { return true }

        let result = Locked<Result<[String], any Error>?>(nil)
        let done = DispatchSemaphore(value: 0)
        let start = ContinuousClock.now
        queryQueue.async { [query] in
            let answer = Result { try query() }
            result.withLock { $0 = answer }
            done.signal()
        }
        guard done.wait(timeout: .now() + limits.queryTimeout) == .success,
              let answer = result.withLock({ $0 })
        else {
            state.withLock { giveUp(&$0, "the Spotlight query took more than \(limits.queryTimeout) s") }
            return false
        }
        let paths: [String]
        switch answer {
        case .success(let found): paths = found
        case .failure(let error):
            state.withLock { giveUp(&$0, "the Spotlight query failed: \(error)") }
            return false
        }
        let elapsed = (ContinuousClock.now - start) / .milliseconds(1)
        let candidates = GameCandidates(paths: paths, home: home)
        var byLocation: [LocationClass: [String]] = [:]
        for candidate in candidates.candidates { byLocation[candidate.location, default: []].append(candidate.path) }

        log.notice(.direct, "Spotlight found \(paths.count) games in \(Int(elapsed)) ms")
        let counts = candidates.countsByLocation
        for location in Set(counts.keys).union(volumes()).sorted() {
            log.notice(.direct, "\(location): \(counts[location] ?? 0)")
        }
        for (reason, count) in candidates.excluded.sorted(by: { $0.key < $1.key }) {
            log.notice(.direct, "Left out, \(reason.rawValue): \(count)")
        }

        return state.withLock { state in
            let now = clock()
            state.queriedAt = now
            var locations: [LocationClass: Location] = [:]
            for (location, paths) in byLocation {
                // A location keeps its health over a new query; only its files change.
                var entry = state.locations[location] ?? Location()
                entry.candidates = paths
                locations[location] = entry
            }
            state.locations = locations
            if locations.isEmpty { giveUp(&state, "Spotlight found no games") }
            return !locations.isEmpty
        }
    }

    /// A random candidate from the open locations, which must hold at least one, each file as
    /// likely as any other: one that isn't in the first avoided set it can avoid, or any.
    private static func choose(from open: [LocationClass: Location], avoiding avoided: [Set<String>],
                               using generator: inout some RandomNumberGenerator) -> (path: String, location: LocationClass) {
        let locations = open.sorted { $0.key < $1.key }
        let total = locations.reduce(0) { $0 + $1.value.candidates.count }
        func random() -> (path: String, location: LocationClass) {
            var index = Int.random(in: 0 ..< total, using: &generator)
            for (location, entry) in locations {
                if index < entry.candidates.count { return (entry.candidates[index], location) }
                index -= entry.candidates.count
            }
            preconditionFailure("The index is below the total.")
        }
        for avoid in avoided {
            for _ in 0 ..< 32 {
                let candidate = random()
                if !avoid.contains(identity(of: candidate.path)) { return candidate }
            }
        }
        return random()
    }

    /// What tells a file's game apart from others: its URL, as the playlist writes it. Made
    /// without looking at the disk, which `URL(fileURLWithPath:)` alone does to learn whether
    /// the path is a folder.
    static func identity(of path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: false).absoluteString
    }

    // MARK: - Reading

    /// Reads a candidate with a time limit and applies the outcome to its location. Returns the
    /// game if it is one.
    private func read(_ path: String, in location: LocationClass) -> SaverGame? {
        /// The read's result, or whether the pick stopped waiting for it.
        struct Pending {
            var result: GameFileReader.Result?
            var abandoned = false
        }
        let pending = Locked(Pending())
        let done = DispatchSemaphore(value: 0)
        let start = ContinuousClock.now
        readQueue.async { [reader] in
            let result = reader.read(path)
            let wasAbandoned = pending.withLock { pending in
                pending.result = result
                return pending.abandoned
            }
            done.signal()
            if wasAbandoned { self.finishLate(result, path: path, location: location, start: start) }
        }
        let result: GameFileReader.Result? = if done.wait(timeout: .now() + limits.readTimeout) == .success {
            pending.withLock { $0.result }
        } else {
            pending.withLock { pending in
                if pending.result == nil { pending.abandoned = true }
                return pending.result
            }
        }
        let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))

        guard let result else {
            log.info(.direct, "\(location): timed out after \(milliseconds) ms, abandoned", path: path)
            state.withLock { state in
                state.blockedReads += 1
                state.failedPicksInARow += 1
                state.locations[location]?.timeoutsInARow += 1
                if let entry = state.locations[location], entry.health == .ok, entry.timeoutsInARow >= limits.timeoutsInARow {
                    deny(&state, location, "\(entry.timeoutsInARow) time-outs in a row")
                }
                if state.blockedReads >= limits.blockedReads {
                    giveUp(&state, "\(state.blockedReads) abandoned reads haven't come back")
                }
            }
            return nil
        }

        log.info(.direct, "\(location): \(result.outcome.name), \(result.bytesRead) bytes, \(milliseconds) ms", path: path)
        return state.withLock { state in
            state.locations[location]?.timeoutsInARow = 0
            switch result.outcome {
            case .game(let game):
                state.failedPicksInARow = 0
                return SaverGame(game: game, source: .direct, identity: Self.identity(of: path))
            case .denied:
                state.locations[location]?.denied += 1
                if let entry = state.locations[location], entry.health == .ok, entry.denied >= limits.deniedOutcomes {
                    deny(&state, location, "\(entry.denied) reads refused (EPERM)")
                }
            case .unreadable:
                state.locations[location]?.unreadable += 1
                if let entry = state.locations[location], entry.health == .ok, entry.unreadable >= limits.unreadableOutcomes {
                    state.locations[location]?.health = .skipped
                    log.notice(.direct, "\(location) skipped: \(entry.unreadable) files unreadable")
                    if !state.locations.values.contains(where: { $0.health == .ok }) {
                        giveUp(&state, "every location is denied or skipped")
                    }
                }
            case .missing, .dataless, .notAGame, .timedOut:
                break
            }
            state.failedPicksInARow += 1
            return nil
        }
    }

    /// A read that was abandoned has come back, and holds its thread no longer. A game from a
    /// denied location means macOS has since allowed it, so the location may be read again.
    private func finishLate(_ result: GameFileReader.Result, path: String, location: LocationClass,
                            start: ContinuousClock.Instant) {
        let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
        log.notice(.direct, "\(location): a read abandoned earlier came back after \(milliseconds) ms: \(result.outcome.name)")
        state.withLock { state in
            state.blockedReads -= 1
            guard case .game = result.outcome, state.locations[location]?.health == .denied else { return }
            state.locations[location]?.health = .ok
            state.locations[location]?.denied = 0
            state.locations[location]?.timeoutsInARow = 0
            log.notice(.direct, "\(location) may be read again")
        }
    }

    private func deny(_ state: inout State, _ location: LocationClass, _ reason: String) {
        state.locations[location]?.health = .denied
        log.notice(.direct, "\(location) denied: \(reason); reading it needs \(location.permission) for legacyScreenSaver")
        if !state.locations.values.contains(where: { $0.health == .ok }) {
            giveUp(&state, "every location is denied or skipped")
        }
    }

    private func giveUp(_ state: inout State, _ reason: String) {
        guard state.givenUp == nil else { return }
        state.givenUp = reason
        log.notice(.direct, "Direct mode gives up: \(reason)")
    }
}

/// A value behind a lock, which escaping closures can share (unlike a `Mutex`, which can't be
/// captured by one).
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&value) }
    }
}
