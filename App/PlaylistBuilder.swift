import Foundation
import Observation
import os
import SGFKit
import Synchronization

/// Chooses the screensaver's games and writes its playlist (see `docs/screensaver.md`, 1.5): it
/// asks macOS for access to the places games are likely to be, when someone has asked for the
/// update (see ``AccessCheck``), asks Spotlight for every qualifying game, reads files in a random
/// order until ``gameLimit`` of them qualify, and writes each one's line (see ``Playlist``). It
/// keeps the playlist already there instead when the new one would have fewer games because
/// files couldn't be read or were hidden (see ``KeptPlaylist``).
///
/// The app does this rather than the screensaver because the files are almost all in places
/// that macOS's privacy settings guard. The app can ask for access while someone is at the Mac,
/// with its own name on the request; the screensaver's host can't.
struct PlaylistBuilder: Sendable {
    /// What a build is doing, for the window.
    enum Stage: Sendable, Equatable {
        /// Reading a place's top level, which waits while macOS asks for access to it.
        case askingForAccess(LocationClass)
        case askingSpotlight
        /// Reading files: the games chosen so far, and the number wanted.
        case choosing(games: Int, wanted: Int)
    }

    /// What happened to the files of one location.
    struct Tally: Sendable, Equatable {
        /// The candidates Spotlight found there.
        var found = 0
        /// The files read, whatever came of it.
        var read = 0
        var games = 0
        var notAGame = 0
        var missing = 0
        var dataless = 0
        var denied = 0
        var unreadable = 0

        mutating func add(_ outcome: GameFileReader.Outcome) {
            read += 1
            switch outcome {
            case .game: games += 1
            case .notAGame: notAGame += 1
            case .missing: missing += 1
            case .dataless: dataless += 1
            case .denied: denied += 1
            case .unreadable: unreadable += 1
            }
        }
    }

    /// What a build did.
    struct Report: Sendable {
        /// When the playlist was made.
        var made: Date
        /// The files Spotlight found.
        var found: Int
        /// The files left out, by reason.
        var excluded: [GameCandidates.Exclusion: Int]
        /// What happened in each location.
        var tallies: [LocationClass: Tally]
        /// The games in the playlist.
        var games: Int
        /// The size of the playlist, in bytes.
        var bytesWritten: Int
        /// How long it took.
        var seconds: Double
        /// The playlist already there, if it was kept rather than replaced.
        var kept: KeptPlaylist?
        /// What came of asking macOS for access to each place, or `nil` if the build didn't
        /// ask, as when the app updates the games by itself.
        var access: [LocationClass: AccessCheck.Access]?

        /// The new playlist's header.
        var header: Playlist.Header { .init(made: made, found: found, games: games) }

        /// The places macOS refused access to, in order.
        var deniedPlaces: [LocationClass] { (access ?? [:]).filter { $0.value == .denied }.keys.sorted() }
    }

    /// A playlist already there that a build kept, rather than replace it with one that has
    /// fewer games because files couldn't be read or found, not because the games are gone:
    /// macOS refused them, a volume isn't connected, or Spotlight hid them. Spotlight's index of a
    /// volume is on the volume, so it finds nothing there while the volume is away, and it leaves
    /// out the files the app isn't allowed to read.
    struct KeptPlaylist: Sendable, Equatable {
        enum Reason: Sendable, Equatable, CustomStringConvertible {
            /// No game could be found or read.
            case noGames
            /// macOS refused some of the reads.
            case refused
            /// Volumes that hold some of the kept playlist's games aren't connected, by name.
            case volumesMissing([String])
            /// Places that macOS's privacy settings guard, which hold some of the kept playlist's
            /// games, where Spotlight found none this time, and where the app either may not be
            /// allowed to read or found the old games still there.
            case hidden([LocationClass])

            var description: String {
                switch self {
                case .noGames: "no games could be found or read"
                case .refused: "macOS refused some reads"
                case .volumesMissing(let names): "not connected: \(names.joined(separator: ", "))"
                case .hidden(let locations): "none found in \(locations.map(\.description).joined(separator: ", "))"
                }
            }
        }

        /// The kept playlist's header.
        var header: Playlist.Header
        var reason: Reason
    }

    /// Why a build failed.
    enum BuildError: Error, Equatable, CustomStringConvertible {
        /// Spotlight couldn't answer.
        case spotlight(String)
        /// The playlist couldn't be written.
        case write(String)

        var description: String {
            switch self {
            case .spotlight(let reason): "Spotlight couldn’t be asked for games: \(reason)."
            case .write(let reason): "The list of games couldn’t be saved: \(reason)."
            }
        }
    }

    /// The most games a playlist holds. A new random set each time means the screensaver works
    /// through a large collection over the weeks.
    var gameLimit = 10_000

    /// The number of files read at a time.
    var concurrentReads = 4

    /// Asks Spotlight for the qualifying files; replaced by the tests.
    var findPaths: @Sendable () throws -> [String] = { try GameCandidates.spotlightPaths() }

    /// The real home folder, for sorting paths into locations.
    var home = Playlist.realHomeDirectory

    /// Reads each file.
    var reader = GameFileReader()

    /// The volumes mounted under `/Volumes`; replaced by the tests.
    var mountedVolumes: @Sendable () -> [LocationClass] = { GameCandidates.mountedVolumes() }

    /// Asks macOS for access to the places games are likely to be; the tests replace its reads.
    var accessCheck = AccessCheck()

    /// The time; replaced by the tests.
    var now: @Sendable () -> Date = { Date() }

    /// The most files of a hidden place that are looked for, to tell whether the games chosen
    /// from there before are gone (see ``playlistToKeep(_:games:tallies:access:mounted:home:exists:)``).
    static let gonePathsChecked = 20

    private static let log = Logger(subsystem: "com.pragmaphilia.SGFTools", category: "playlist")

    /// Chooses games and writes the playlist to `url`, replacing any file there in one step, so
    /// that the screensaver reads the old playlist or the new one, never part of one, unless the
    /// old one is kept (see ``KeptPlaylist``). There is no time limit: a read that waits on a
    /// permission request waits for the answer.
    ///
    /// - Parameters:
    ///   - askingForAccess: Whether to ask macOS for access to the places games are likely to be
    ///     first (see ``AccessCheck``): only when someone has just asked for the update, since
    ///     macOS may put up a request for each place.
    ///   - progress: Called at each stage, and after each batch of reads, on the builder's thread.
    func build(
        writingTo url: URL, askingForAccess: Bool, using generator: inout some RandomNumberGenerator,
        progress: @Sendable (Stage) -> Void = { _ in }
    ) throws(BuildError) -> Report {
        let clock = ContinuousClock()
        let start = clock.now
        let access = askingForAccess ? accessCheck.run { progress(.askingForAccess($0.location)) } : nil
        progress(.askingSpotlight)
        let paths: [String]
        do {
            paths = try findPaths()
        } catch {
            Self.log.error("Spotlight failed: \(String(describing: error), privacy: .public)")
            throw .spotlight(String(describing: error))
        }
        let candidates = GameCandidates(paths: paths, home: home)
        var tallies: [LocationClass: Tally] = [:]
        for (location, count) in candidates.countsByLocation { tallies[location, default: Tally()].found = count }

        let order = candidates.candidates.shuffled(using: &generator)
        let wanted = min(gameLimit, order.count)
        var lines: [String] = []
        lines.reserveCapacity(wanted)
        var next = 0
        progress(.choosing(games: 0, wanted: wanted))
        while lines.count < gameLimit, next < order.count {
            let batch = Array(order[next ..< min(next + concurrentReads * 16, order.count)])
            next += batch.count
            for (candidate, result) in zip(batch, read(batch)) where lines.count < gameLimit {
                tallies[candidate.location, default: Tally()].add(result.outcome)
                if case .game(let game) = result.outcome,
                   let line = Playlist.line(for: game, url: URL(fileURLWithPath: candidate.path, isDirectory: false)) {
                    lines.append(line)
                }
            }
            progress(.choosing(games: lines.count, wanted: wanted))
        }

        let made = now()
        if let kept = playlistToKeep(at: url, games: lines.count, tallies: tallies, access: access) {
            let report = Report(made: made, found: candidates.found, excluded: candidates.excluded, tallies: tallies,
                                games: lines.count, bytesWritten: 0, seconds: (clock.now - start) / .seconds(1),
                                kept: kept, access: access)
            Self.logReport(report)
            return report
        }
        var text = Playlist.text(of: .init(made: made, found: candidates.found, games: lines.count))
        for line in lines { text += line + "\n" }
        let data = Data(text.utf8)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            let nsError = error as NSError
            let reason = "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
            Self.log.error("Writing the playlist failed: \(reason, privacy: .public)")
            throw .write(reason)
        }

        let report = Report(made: made, found: candidates.found, excluded: candidates.excluded, tallies: tallies,
                            games: lines.count, bytesWritten: data.count,
                            seconds: (clock.now - start) / .seconds(1), access: access)
        Self.logReport(report)
        return report
    }

    /// The playlist at `url`, if the new one mustn't replace it (see
    /// ``playlistToKeep(_:games:tallies:access:mounted:home:exists:)``).
    private func playlistToKeep(at url: URL, games: Int, tallies: [LocationClass: Tally],
                                access: [LocationClass: AccessCheck.Access]?) -> KeptPlaylist? {
        guard case .success(let data) = GameFileReader.readPrefix(ofFileAt: url.path, limit: Playlist.sizeLimit),
              let old = try? Playlist.Contents(data: data)
        else { return nil }
        let status = reader.status
        let kept = Self.playlistToKeep(old, games: games, tallies: tallies, access: access, mounted: Set(mountedVolumes()),
                                       home: home.standardizedFileURL.path) { path in
            if case .success = status(path) { true } else { false }
        }
        if case .hidden(let locations)? = kept?.reason {
            for location in locations where access?[location] == .allowed {
                Self.log.notice("""
                    Spotlight found no games in \(location.description, privacy: .public), though SGF Tools may read it \
                    and games chosen there before are still there
                    """)
            }
        }
        return kept
    }

    /// Whether to keep the playlist already there, `old`, rather than replace it with a new one
    /// of `games` games, and why. **A build never replaces a playlist with one that has fewer
    /// games because of files it couldn't read or find, only because the games are gone**, so it
    /// keeps the old one when the new one would have fewer games and
    /// - it has none
    /// - macOS refused some reads
    /// - a volume that holds some of the old games isn't connected
    /// - a place that macOS's privacy settings guard holds some of the old games, and Spotlight
    ///   found none there this time. Spotlight leaves out the files the app may not read, so the
    ///   games may be hidden rather than gone. Only when the build asked for access to the place
    ///   and got it, and none of the first ``gonePathsChecked`` old games there still exists, are
    ///   they gone. Without access, nothing there is looked at, since macOS might ask.
    ///
    /// - Parameters:
    ///   - access: What came of asking for access to each place, or `nil` if the build didn't ask.
    ///   - mounted: The volumes mounted under `/Volumes`.
    ///   - home: The real home folder's path.
    ///   - exists: Whether a file is there.
    static func playlistToKeep(
        _ old: Playlist.Contents, games: Int, tallies: [LocationClass: Tally], access: [LocationClass: AccessCheck.Access]?,
        mounted: Set<LocationClass>, home: String, exists: (String) -> Bool
    ) -> KeptPlaylist? {
        guard old.count > games else { return nil }
        if games == 0 { return KeptPlaylist(header: old.header, reason: .noGames) }
        if tallies.values.contains(where: { $0.denied > 0 }) { return KeptPlaylist(header: old.header, reason: .refused) }
        var oldPaths: [LocationClass: [String]] = [:]
        for index in 0 ..< old.count {
            guard let path = old.url(at: index).flatMap(URL.init(string:))?.path else { continue }
            oldPaths[GameCandidates.location(of: path, home: home), default: []].append(path)
        }
        let missing = oldPaths.keys.compactMap { location -> String? in
            guard case .volume(let name) = location, !mounted.contains(location) else { return nil }
            return name
        }
        if !missing.isEmpty { return KeptPlaylist(header: old.header, reason: .volumesMissing(missing.sorted())) }
        let hidden = oldPaths.filter { location, paths in
            location.isGuarded && (tallies[location]?.found ?? 0) == 0
                && (access?[location] != .allowed || paths.prefix(gonePathsChecked).contains(where: exists))
        }
        return hidden.isEmpty ? nil : KeptPlaylist(header: old.header, reason: .hidden(hidden.keys.sorted()))
    }

    /// Reads a batch of files, ``concurrentReads`` at a time, and returns the results in the
    /// batch's order.
    private func read(_ batch: [GameCandidates.Candidate]) -> [GameFileReader.Result] {
        let results = Mutex<[GameFileReader.Result?]>(Array(repeating: nil, count: batch.count))
        let workers = max(1, concurrentReads)
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            for index in stride(from: worker, to: batch.count, by: workers) {
                let result = reader.read(batch[index].path)
                results.withLock { $0[index] = result }
            }
        }
        return results.withLock { $0.map { $0! } }
    }

    private static func logReport(_ report: Report) {
        let excluded = report.excluded.sorted { $0.key < $1.key }.map { "\($0.key.rawValue) \($0.value)" }
        if let kept = report.kept {
            log.notice("""
                Kept the playlist of \(kept.header.games, privacy: .public) games made \
                \(kept.header.made.formatted(.iso8601), privacy: .public): \(String(describing: kept.reason), privacy: .public); \
                the new one would have had \(report.games, privacy: .public) games of \(report.found, privacy: .public) found, \
                in \(report.seconds, format: .fixed(precision: 2), privacy: .public) s; \
                left out: \(excluded.isEmpty ? "none" : excluded.joined(separator: ", "), privacy: .public)
                """)
        } else {
            log.notice("""
                Wrote \(report.games, privacy: .public) games of \(report.found, privacy: .public) found, \
                \(report.bytesWritten, privacy: .public) bytes, in \(report.seconds, format: .fixed(precision: 2), privacy: .public) s; \
                left out: \(excluded.isEmpty ? "none" : excluded.joined(separator: ", "), privacy: .public)
                """)
        }
        for (location, tally) in report.tallies.sorted(by: { $0.key < $1.key }) {
            log.notice("""
                \(location.description, privacy: .public): found \(tally.found, privacy: .public), \
                read \(tally.read, privacy: .public), games \(tally.games, privacy: .public), \
                not a game \(tally.notAGame, privacy: .public), missing \(tally.missing, privacy: .public), \
                dataless \(tally.dataless, privacy: .public), denied \(tally.denied, privacy: .public), \
                unreadable \(tally.unreadable, privacy: .public)
                """)
        }
    }
}

/// The screensaver's games as the app's window shows them: what the playlist holds, the
/// progress of an update, and what went wrong.
@MainActor
@Observable
final class ScreensaverGames {
    /// The one the app's window shows.
    static let shared = ScreensaverGames()

    /// A playlist older than this is replaced when the app opens, if the screensaver is
    /// installed.
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    /// What the window says about the games.
    private(set) var status = "No games have been chosen yet."

    /// What went wrong in the last update, a line each.
    private(set) var problems: [String] = []

    /// The pane of System Settings that would let the app read the places macOS refused it in
    /// the last update, if any.
    private(set) var settingsPane: PrivacySetting.Pane?

    /// Whether an update is running.
    private(set) var isUpdating = false

    /// What to do when the update under way finishes.
    private var afterUpdateActions: [@MainActor () -> Void] = []

    let playlistURL: URL

    /// Builds the playlist; the tests replace its Spotlight query, reads, and access check.
    private let builder: PlaylistBuilder

    init(playlistURL: URL = Playlist.defaultURL, builder: PlaylistBuilder = PlaylistBuilder()) {
        self.playlistURL = playlistURL
        self.builder = builder
    }

    /// When the app opens: shows what the playlist holds, and chooses new games if the
    /// screensaver is installed and the playlist is missing or more than a week old. Someone who
    /// never installs the screensaver never sees a permission request.
    func appDidLaunch() {
        let url = playlistURL
        Task.detached(priority: .utility) {
            let header = ScreensaverGames.header(ofPlaylistAt: url)
            let installed = ScreensaverGames.isScreensaverInstalled()
            await self.show(header, updatingIfStale: installed)
        }
    }

    /// Chooses new games and writes the playlist, off the main thread.
    ///
    /// - Parameter askingForAccess: Whether to ask macOS for access to the places games are
    ///   likely to be first, which may put up a request for each (see ``AccessCheck``): when
    ///   someone clicks Update Screensaver Games, never when the app updates the games by itself.
    func update(askingForAccess: Bool = true) {
        guard !isUpdating else { return }
        isUpdating = true
        problems = []
        settingsPane = nil
        status = askingForAccess ? "Asking macOS for access…" : Self.describe(.askingSpotlight)
        let (url, builder) = (playlistURL, builder)
        Task.detached(priority: .utility) {
            var generator = SystemRandomNumberGenerator()
            let result: Result<PlaylistBuilder.Report, PlaylistBuilder.BuildError>
            do throws(PlaylistBuilder.BuildError) {
                result = .success(try builder.build(writingTo: url, askingForAccess: askingForAccess, using: &generator) { stage in
                    Task { @MainActor in self.show(stage) }
                })
            } catch {
                result = .failure(error)
            }
            await self.finish(result)
        }
    }

    /// Runs `action` once no update is running: at once, or when the one under way finishes. The
    /// app quits this way, so that closing its window doesn't throw away the files read so far.
    func afterUpdate(_ action: @escaping @MainActor () -> Void) {
        guard isUpdating else { return action() }
        afterUpdateActions.append(action)
    }

    /// Shows what a playlist holds, and chooses new games if the screensaver is installed and
    /// the playlist is missing or more than a week old, without asking macOS for access.
    func show(_ header: Playlist.Header?, updatingIfStale installed: Bool) {
        guard !isUpdating else { return }
        if let header { status = Self.describe(header, now: Date()) }
        if installed, header.map({ Date().timeIntervalSince($0.made) > Self.maximumAge }) ?? true {
            update(askingForAccess: false)
        }
    }

    private func show(_ stage: PlaylistBuilder.Stage) {
        guard isUpdating else { return }
        status = Self.describe(stage)
    }

    private func finish(_ result: Result<PlaylistBuilder.Report, PlaylistBuilder.BuildError>) {
        isUpdating = false
        switch result {
        case .success(let report):
            (status, problems) = Self.describe(report, now: Date())
            settingsPane = report.deniedPlaces.first?.permission.pane
        case .failure(let error):
            status = error.description
            problems = []
        }
        let actions = afterUpdateActions
        afterUpdateActions = []
        for action in actions { action() }
    }

    // MARK: - Wording

    /// What the window says while a build is at a stage, such as "Asking macOS for access to
    /// Documents…" or "Choosing games… 2,345 of 10,000".
    nonisolated static func describe(_ stage: PlaylistBuilder.Stage, locale: Locale = .current) -> String {
        switch stage {
        case .askingForAccess(let location): "Asking macOS for access to \(location)…"
        case .askingSpotlight: "Asking Spotlight for games…"
        case .choosing(let games, let wanted):
            "Choosing games… \(games.formatted(.number.locale(locale))) of \(wanted.formatted(.number.locale(locale)))"
        }
    }

    /// The status line and the problems after a build.
    nonisolated static func describe(_ report: PlaylistBuilder.Report, now: Date, locale: Locale = .current,
                                     calendar: Calendar = .current) -> (status: String, problems: [String]) {
        var status: String
        var problems: [String] = []
        if let kept = report.kept {
            status = describe(kept.header, now: now, locale: locale, calendar: calendar)
            problems.append(describe(kept, games: report.games, locale: locale))
        } else if report.found == 0 {
            status = report.deniedPlaces.isEmpty
                ? "Spotlight found no games that name both players and have at least \(Playlist.minimumMoves) moves."
                : "Spotlight found no games that SGF Tools is allowed to read."
        } else {
            status = describe(report.header, now: now, locale: locale, calendar: calendar)
        }
        if let advice = accessAdvice(for: report, locale: locale) { problems.append(advice) }
        return (status, problems + self.problems(in: report, locale: locale))
    }

    /// What to do about the places macOS doesn't let the app read, if that may be why games are
    /// missing, such as "SGF Tools isn’t allowed to read Documents, so macOS hides the games
    /// there. …". After an update that asked for access, it names the places refused; after one
    /// that didn't, and found no games or kept the ones before because Spotlight found none in
    /// their places, it says to click the button, which asks.
    nonisolated static func accessAdvice(for report: PlaylistBuilder.Report, locale: Locale = .current) -> String? {
        let denied = report.deniedPlaces
        if !denied.isEmpty {
            let places = denied.map(\.description).formatted(.list(type: .or).locale(locale))
            var switches: [String] = []
            for item in denied.compactMap(\.permission.item) where !switches.contains(item) { switches.append(item) }
            let panes = Set(denied.map(\.permission.pane.rawValue)).sorted().joined(separator: " or ")
            return """
                SGF Tools isn’t allowed to read \(places), so macOS hides the games there. To allow it, turn on \
                \(switches.formatted(.list(type: .and).locale(locale))) for SGF Tools in System Settings > Privacy & \
                Security > \(panes), then click Update Screensaver Games again.
                """
        }
        let hidden = if case .hidden = report.kept?.reason { true } else { false }
        guard report.access == nil, report.games == 0 || hidden else { return nil }
        return """
            macOS hides the games SGF Tools isn’t allowed to read. Click Update Screensaver Games to let SGF Tools ask \
            for access to Documents and your other disks.
            """
    }

    /// "10,000 games of 64,020, chosen today at 10:32".
    nonisolated static func describe(_ header: Playlist.Header, now: Date, locale: Locale = .current,
                         calendar: Calendar = .current) -> String {
        let found = header.found.formatted(.number.locale(locale))
        return "\(games(header.games, locale: locale)) of \(found), chosen \(describe(header.made, now: now, locale: locale, calendar: calendar))"
    }

    /// "today at 10:32", "yesterday at 10:32", or "on Sep 20, 2026 at 10:32".
    nonisolated static func describe(_ date: Date, now: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                                   calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday at \(time)"
        }
        let day = date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale,
                                                  calendar: calendar, timeZone: calendar.timeZone))
        return "on \(day) at \(time)"
    }

    /// Why the games chosen before were kept, such as "Only 441 games could be read this time, so
    /// the games chosen before are kept."
    nonisolated static func describe(_ kept: PlaylistBuilder.KeptPlaylist, games: Int, locale: Locale = .current) -> String {
        let reason = switch kept.reason {
        case .noGames: "No games could be found or read this time"
        case .refused: "Only \(Self.games(games, locale: locale)) could be read this time"
        case .volumesMissing(let names) where names.count == 1: "The volume \(names[0]) isn’t connected"
        case .volumesMissing(let names): "The volumes \(names.formatted(.list(type: .and).locale(locale))) aren’t connected"
        case .hidden(let locations):
            "Spotlight found no games in \(locations.map(\.description).formatted(.list(type: .or).locale(locale))) this time"
        }
        return "\(reason), so the games chosen before are kept."
    }

    /// A line for each location where files couldn't be read, such as "441 games in Documents
    /// couldn't be read: access not allowed".
    nonisolated static func problems(in report: PlaylistBuilder.Report, locale: Locale = .current) -> [String] {
        var lines: [String] = []
        for (location, tally) in report.tallies.sorted(by: { $0.key < $1.key }) {
            if tally.denied > 0 {
                lines.append("\(games(tally.denied, locale: locale)) in \(location) couldn’t be read: access not allowed")
            }
            if tally.unreadable > 0 {
                lines.append("\(games(tally.unreadable, locale: locale)) in \(location) couldn’t be read")
            }
        }
        return lines
    }

    nonisolated private static func games(_ count: Int, locale: Locale) -> String {
        count == 1 ? "1 game" : "\(count.formatted(.number.locale(locale))) games"
    }

    // MARK: - Files

    /// The header of the playlist at a URL, or `nil` if there is none that can be read. Only
    /// the start of the file is read.
    nonisolated static func header(ofPlaylistAt url: URL) -> Playlist.Header? {
        guard case .success(let data) = GameFileReader.readPrefix(ofFileAt: url.path, limit: 4096) else { return nil }
        return try? Playlist.Contents(data: data).header
    }

    /// Whether `SGF Tools.saver` is in the user's or the computer's Screen Savers folder.
    nonisolated static func isScreensaverInstalled(home: URL = Playlist.realHomeDirectory) -> Bool {
        let folders = [home.appendingPathComponent("Library/Screen Savers"), URL(fileURLWithPath: "/Library/Screen Savers")]
        return folders.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("SGF Tools.saver").path) }
    }
}
