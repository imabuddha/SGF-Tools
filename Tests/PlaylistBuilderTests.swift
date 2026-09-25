import Darwin
import Foundation
import SGFKit
import Testing

@Suite("Playlist: the app's builder")
struct PlaylistBuilderTests {
    static let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    static let made = Date(timeIntervalSince1970: 1_790_000_000)

    /// A builder whose Spotlight answers `paths` and whose reads answer by path: a path with
    /// "denied", "locked", "gone", "cloud", or "problem" in it gives that outcome, and any other
    /// a game with 30 + its number of moves.
    static func builder(paths: [String], limit: Int = 10) -> PlaylistBuilder {
        var builder = PlaylistBuilder()
        builder.gameLimit = limit
        builder.home = home
        builder.findPaths = { paths }
        builder.now = { made }
        builder.reader.status = { path in
            if path.contains("gone") { return .failure(.init(code: ENOENT)) }
            return .success(.init(inode: 1, size: 1000, modified: [0, 0], isDataless: path.contains("cloud")))
        }
        builder.reader.readPrefix = { path, _ in
            if path.contains("denied") { return .failure(.init(code: EPERM)) }
            if path.contains("locked") { return .failure(.init(code: EACCES)) }
            if path.contains("problem") { return .success(Data("(;AB[dd];W[pp])".utf8)) }
            let number = Int(path.filter(\.isNumber)) ?? 0
            return .success(Data(namedGame(moves: 30 + number % 20).utf8))
        }
        return builder
    }

    static func gamePaths(_ count: Int, in folder: String = "/Volumes/Disk/Games") -> [String] {
        (0 ..< count).map { "\(folder)/game \($0).sgf" }
    }

    @Test func holdsTenThousandGamesAtMost() {
        #expect(PlaylistBuilder().gameLimit == 10_000)
    }

    @Test func stopsAtTheLimit() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("SGF Tools/Screensaver Games.sgfplaylist")
        var generator = SeededGenerator(seed: 1)
        let progress = Counter()
        let report = try Self.builder(paths: Self.gamePaths(30), limit: 10)
            .build(writingTo: url, using: &generator) { games, wanted in
                #expect(wanted == 10)
                #expect(games <= 10)
                progress.increment()
            }
        #expect(report.games == 10)
        #expect(report.found == 30)
        #expect(progress.value >= 2)
        let contents = try Playlist.Contents(data: Data(contentsOf: url))
        #expect(contents.header == .init(made: Self.made, found: 30, games: 10))
        #expect(contents.count == 10)
        #expect(report.bytesWritten == (try Data(contentsOf: url)).count)
        // Each game once, from the files it came from.
        let urls = (0 ..< contents.count).compactMap { contents.entry(at: $0)?.url }
        #expect(Set(urls).count == 10)
        #expect(urls.allSatisfy { $0.hasPrefix("file:///Volumes/Disk/Games/game%20") })
    }

    @Test func theSameSeedGivesTheSameFile() throws {
        let folder = try TemporaryFolder()
        let paths = Self.gamePaths(40)
        func build(seed: UInt64, name: String) throws -> Data {
            let url = folder.url.appendingPathComponent(name)
            var generator = SeededGenerator(seed: seed)
            _ = try Self.builder(paths: paths, limit: 15).build(writingTo: url, using: &generator)
            return try Data(contentsOf: url)
        }
        let first = try build(seed: 7, name: "a")
        #expect(try build(seed: 7, name: "b") == first)
        #expect(try build(seed: 8, name: "c") != first)
    }

    @Test func talliesEachLocation() throws {
        let folder = try TemporaryFolder()
        let paths = Self.gamePaths(5)
            + ["/Users/tester/Documents/denied 1.sgf", "/Users/tester/Documents/denied 2.sgf",
               "/Users/tester/Documents/game 3.sgf",
               "/Users/tester/Downloads/locked.sgf", "/Users/tester/Go/gone.sgf", "/Users/tester/Go/cloud.sgf",
               "/Users/tester/Go/problem.sgf",
               "/Users/tester/Library/Containers/x/game 1.sgf", "/Users/tester/.Trash/game 2.sgf"]
        var generator = SeededGenerator(seed: 3)
        let report = try Self.builder(paths: paths, limit: 100)
            .build(writingTo: folder.url.appendingPathComponent("playlist"), using: &generator)
        #expect(report.found == 14)
        #expect(report.games == 6)
        #expect(report.excluded == [.library: 1, .trash: 1])
        #expect(report.tallies[.volume("Disk")] == .init(found: 5, read: 5, games: 5))
        #expect(report.tallies[.documents] == .init(found: 3, read: 3, games: 1, denied: 2))
        #expect(report.tallies[.downloads] == .init(found: 1, read: 1, unreadable: 1))
        #expect(report.tallies[.home] == .init(found: 3, read: 3, notAGame: 1, missing: 1, dataless: 1))

        let problems = ScreensaverGames.problems(in: report, locale: Locale(identifier: "en_US"))
        #expect(problems == [
            "2 games in Documents couldn’t be read: access not allowed",
            "1 game in Downloads couldn’t be read",
        ])
    }

    @Test func replacesThePlaylistInOneStep() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("Screensaver Games.sgfplaylist")
        var generator = SeededGenerator(seed: 5)
        _ = try Self.builder(paths: Self.gamePaths(20), limit: 5).build(writingTo: url, using: &generator)
        let before = try GameFileReader.status(ofFileAt: url.path).get()
        let old = try Data(contentsOf: url)
        _ = try Self.builder(paths: Self.gamePaths(20), limit: 8).build(writingTo: url, using: &generator)
        let after = try GameFileReader.status(ofFileAt: url.path).get()
        // A new file renamed into place, not the old one written over, and nothing left beside it.
        #expect(after.inode != before.inode)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == [url.lastPathComponent])
        #expect(try Playlist.Contents(data: old).count == 5)
        #expect(try Playlist.Contents(data: Data(contentsOf: url)).count == 8)
    }

    @Test func reportsAFolderItCannotWrite() throws {
        let folder = try TemporaryFolder()
        let locked = folder.url.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        #expect(chmod(locked.path, 0o555) == 0)
        var generator = SeededGenerator(seed: 1)
        let error = #expect(throws: PlaylistBuilder.BuildError.self) {
            try Self.builder(paths: Self.gamePaths(3)).build(writingTo: locked.appendingPathComponent("playlist"),
                                                             using: &generator)
        }
        guard case .write(let reason) = error else {
            Issue.record("expected a write error, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("NSCocoaErrorDomain"))
    }

    @Test func reportsSpotlightFailing() throws {
        struct Failure: Error {}
        var builder = Self.builder(paths: [])
        builder.findPaths = { throw Failure() }
        var generator = SeededGenerator(seed: 1)
        let folder = try TemporaryFolder()
        #expect(throws: PlaylistBuilder.BuildError.spotlight("Failure()")) {
            try builder.build(writingTo: folder.url.appendingPathComponent("playlist"), using: &generator)
        }
    }

    @Test func noGamesFoundStillWritesAPlaylist() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        var generator = SeededGenerator(seed: 1)
        let report = try Self.builder(paths: []).build(writingTo: url, using: &generator)
        #expect(report.games == 0 && report.found == 0)
        #expect(try Playlist.Contents(data: Data(contentsOf: url)).count == 0)
    }
}

@Suite("Playlist: the app's window")
struct ScreensaverGamesTests {
    static let locale = Locale(identifier: "en_US")
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    @Test func describesThePlaylist() throws {
        let made = try Date("2026-09-25T01:32:00Z", strategy: .iso8601)  // 10:32 in Tokyo
        let header = Playlist.Header(made: made, found: 64_020, games: 10_000)
        func describe(now: String) throws -> String {
            ScreensaverGames.describe(header, now: try Date(now, strategy: .iso8601), locale: Self.locale,
                                      calendar: Self.calendar)
                .replacingOccurrences(of: "\u{202F}", with: " ")  // before AM
        }
        #expect(try describe(now: "2026-09-25T05:00:00Z") == "10,000 games of 64,020, chosen today at 10:32 AM")
        #expect(try describe(now: "2026-09-26T05:00:00Z") == "10,000 games of 64,020, chosen yesterday at 10:32 AM")
        #expect(try describe(now: "2026-10-05T05:00:00Z") == "10,000 games of 64,020, chosen on Sep 25, 2026 at 10:32 AM")
        let one = Playlist.Header(made: made, found: 1, games: 1)
        #expect(ScreensaverGames.describe(one, now: made, locale: Self.locale, calendar: Self.calendar)
            .replacingOccurrences(of: "\u{202F}", with: " ") == "1 game of 1, chosen today at 10:32 AM")
    }

    @Test func readsOnlyTheHeaderOfALargePlaylist() throws {
        let folder = try TemporaryFolder()
        let line = try #require(Playlist.line(for: try game(namedGame()), url: URL(fileURLWithPath: "/tmp/a.sgf")))
        let made = Date(timeIntervalSince1970: 1_790_000_000)
        let path = try folder.write(playlistText(Array(repeating: line, count: 100), found: 500, made: made),
                                    to: "Screensaver Games.sgfplaylist")
        let header = ScreensaverGames.header(ofPlaylistAt: URL(fileURLWithPath: path))
        #expect(header == .init(made: made, found: 500, games: 100))
        #expect(ScreensaverGames.header(ofPlaylistAt: folder.url.appendingPathComponent("none")) == nil)
    }

    @Test func findsTheInstalledScreensaver() throws {
        let folder = try TemporaryFolder()
        let savers = folder.url.appendingPathComponent("Library/Screen Savers/SGF Tools.saver/Contents")
        try FileManager.default.createDirectory(at: savers, withIntermediateDirectories: true)
        #expect(ScreensaverGames.isScreensaverInstalled(home: folder.url))
        let empty = try TemporaryFolder()
        if !FileManager.default.fileExists(atPath: "/Library/Screen Savers/SGF Tools.saver") {
            #expect(!ScreensaverGames.isScreensaverInstalled(home: empty.url))
        }
    }
}
