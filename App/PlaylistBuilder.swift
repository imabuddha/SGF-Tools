import Foundation
import Observation
import os
import SGFKit
import Synchronization

/// Chooses the screensaver's games and writes its playlist (see `docs/screensaver.md`, 1.5): it
/// asks Spotlight for every qualifying game, reads files in a random order until
/// ``gameLimit`` of them qualify, and writes each one's line (see ``Playlist``).
///
/// The app does this rather than the screensaver because the files are almost all in places
/// that macOS's privacy settings guard. The app can ask for access while someone is at the Mac,
/// with its own name on the request; the screensaver's host can't.
struct PlaylistBuilder: Sendable {
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
            case .denied, .timedOut: denied += 1
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

        /// The playlist's header.
        var header: Playlist.Header { .init(made: made, found: found, games: games) }
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
    /// through a large collection over the weeks: at a minute a game, 10,000 games are about a
    /// week of screensaver time on each display.
    var gameLimit = 10_000

    /// The number of files read at a time.
    var concurrentReads = 4

    /// Asks Spotlight for the qualifying files; replaced by the tests.
    var findPaths: @Sendable () throws -> [String] = { try GameCandidates.spotlightPaths() }

    /// The real home folder, for sorting paths into locations.
    var home = Playlist.realHomeDirectory

    /// Reads each file.
    var reader = GameFileReader()

    /// The time; replaced by the tests.
    var now: @Sendable () -> Date = { Date() }

    private static let log = Logger(subsystem: "com.pragmaphilia.SGFTools", category: "playlist")

    /// Chooses games and writes the playlist to `url`, replacing any file there in one step, so
    /// that the screensaver reads the old playlist or the new one, never part of one. There is
    /// no time limit: a read that waits on a permission request waits for the answer.
    ///
    /// - Parameter progress: Called after each batch of reads with the games chosen so far and
    ///   the number wanted, on the builder's thread.
    func build(
        writingTo url: URL, using generator: inout some RandomNumberGenerator,
        progress: @Sendable (_ games: Int, _ wanted: Int) -> Void = { _, _ in }
    ) throws(BuildError) -> Report {
        let clock = ContinuousClock()
        let start = clock.now
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
        progress(0, wanted)
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
            progress(lines.count, wanted)
        }

        let made = now()
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
                            seconds: (clock.now - start) / .seconds(1))
        Self.logReport(report)
        return report
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
        log.notice("""
            Wrote \(report.games, privacy: .public) games of \(report.found, privacy: .public) found, \
            \(report.bytesWritten, privacy: .public) bytes, in \(report.seconds, format: .fixed(precision: 2), privacy: .public) s; \
            left out: \(excluded.isEmpty ? "none" : excluded.joined(separator: ", "), privacy: .public)
            """)
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

    /// Whether an update is running.
    private(set) var isUpdating = false

    let playlistURL: URL

    init(playlistURL: URL = Playlist.defaultURL) {
        self.playlistURL = playlistURL
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
    func update() {
        guard !isUpdating else { return }
        isUpdating = true
        problems = []
        status = "Asking Spotlight for games…"
        let url = playlistURL
        Task.detached(priority: .utility) {
            var generator = SystemRandomNumberGenerator()
            let result: Result<PlaylistBuilder.Report, PlaylistBuilder.BuildError>
            do throws(PlaylistBuilder.BuildError) {
                result = .success(try PlaylistBuilder().build(writingTo: url, using: &generator) { games, wanted in
                    Task { @MainActor in self.showProgress(games: games, of: wanted) }
                })
            } catch {
                result = .failure(error)
            }
            await self.finish(result)
        }
    }

    private func show(_ header: Playlist.Header?, updatingIfStale installed: Bool) {
        guard !isUpdating else { return }
        if let header { status = Self.describe(header, now: Date()) }
        if installed, header.map({ Date().timeIntervalSince($0.made) > Self.maximumAge }) ?? true {
            update()
        }
    }

    private func showProgress(games: Int, of wanted: Int) {
        guard isUpdating else { return }
        status = "Choosing games… \(games.formatted()) of \(wanted.formatted())"
    }

    private func finish(_ result: Result<PlaylistBuilder.Report, PlaylistBuilder.BuildError>) {
        isUpdating = false
        switch result {
        case .success(let report):
            status = report.found == 0
                ? "Spotlight found no games that name both players and have at least \(Playlist.minimumMoves) moves."
                : Self.describe(report.header, now: Date())
            problems = Self.problems(in: report)
        case .failure(let error):
            status = error.description
            problems = []
        }
    }

    // MARK: - Wording

    /// "10,000 games of 64,020, chosen today at 10:32".
    nonisolated static func describe(_ header: Playlist.Header, now: Date, locale: Locale = .current,
                         calendar: Calendar = .current) -> String {
        let games = header.games.formatted(.number.locale(locale))
        let found = header.found.formatted(.number.locale(locale))
        let count = header.games == 1 ? "1 game" : "\(games) games"
        return "\(count) of \(found), chosen \(describe(header.made, now: now, locale: locale, calendar: calendar))"
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
