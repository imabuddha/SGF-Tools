import Darwin
import Foundation
import SGFKit
import Testing

@Suite("Screensaver: the game library")
struct ScreensaverLibraryTests {
    static let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    static func direct(_ paths: [String], log: RecordingLog, queries: Counter? = nil,
                       limits: DirectSource.Limits = .init()) -> DirectSource {
        DirectSource(query: { queries?.increment(); return paths }, reader: scriptedReader(), home: home,
                     volumes: { [] }, limits: limits, log: log)
    }

    @Test func picksFromThePlaylistFirst() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("Screensaver Games.sgfplaylist")
        try writePlaylist(3, to: url)
        let log = RecordingLog()
        let library = GameLibrary(playlist: PlaylistStore(url: url, log: log),
                                  direct: Self.direct(["/Volumes/Disk/a.sgf"], log: log), ownGame: ownGame, log: log,
                                  generator: SeededGenerator(seed: 1))
        let game = try #require(library.pick(for: 1, allowsDirect: true))
        #expect(game.source == .playlist)
        #expect(game.identity.hasPrefix("file:///Games/game%20"))
        #expect(game.moveCount == 30)
        #expect(game.details.lines.first == .init(kind: .black, text: "Black Tester 3d"))
        #expect(log.messages(.playlist, level: .notice).contains { $0.contains("3 games of 3 found") })
    }

    @Test func thenDirectModeThenItsOwnGame() throws {
        let folder = try TemporaryFolder()
        let log = RecordingLog()
        let missing = PlaylistStore(url: folder.url.appendingPathComponent("none"), log: log)
        let library = GameLibrary(playlist: missing, direct: Self.direct(["/Volumes/Disk/a.sgf"], log: log),
                                  ownGame: ownGame, log: log, generator: SeededGenerator(seed: 1))
        let direct = try #require(library.pick(for: 1, allowsDirect: true))
        #expect(direct.source == .direct)
        #expect(direct.identity == "file:///Volumes/Disk/a.sgf")
        #expect(missing.state == .missing)
        #expect(log.messages(.playlist, level: .notice).contains("The playlist can't be read: no playlist (ENOENT)"))

        struct Failure: Error {}
        let broken = DirectSource(query: { throw Failure() }, reader: scriptedReader(), home: Self.home,
                                  volumes: { [] }, log: log)
        let fallback = GameLibrary(playlist: missing, direct: broken, ownGame: ownGame, log: log)
        let own = try #require(fallback.pick(for: 1, allowsDirect: true))
        #expect(own.source == .own)
        #expect(own.details.lines.last == .init(kind: .other, text: "Open SGF Tools to choose games for this screensaver."))
        #expect(own.details.lines.first?.text == "John Mifsud 15k")
        #expect(own.moveCount == 50)
        #expect(broken.reasonGivenUp?.contains("failed") == true)
    }

    @Test func aPreviewNeverUsesDirectMode() throws {
        let folder = try TemporaryFolder()
        let log = RecordingLog()
        let queries = Counter()
        let library = GameLibrary(playlist: PlaylistStore(url: folder.url.appendingPathComponent("none"), log: log),
                                  direct: Self.direct(["/Volumes/Disk/a.sgf"], log: log, queries: queries),
                                  ownGame: ownGame, log: log)
        let game = try #require(library.pick(for: 1, allowsDirect: false))
        #expect(game.source == .own)
        #expect(queries.value == 0)
    }

    @Test func noGameIsOnTwoScreensAtOnce() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        try writePlaylist(3, to: url)
        let log = RecordingLog()
        let library = GameLibrary(playlist: PlaylistStore(url: url, log: log), direct: nil, ownGame: ownGame, log: log,
                                  generator: SeededGenerator(seed: 4))
        let games = try (1 ... 3).map { try #require(library.pick(for: $0, allowsDirect: true)).identity }
        #expect(Set(games).count == 3)
        // Screen 1's next game, while its first plays: the other screens' games are avoided, so
        // it can only be its own again.
        let next = try #require(library.pick(for: 1, allowsDirect: true))
        #expect(next.identity == games[0])
        // Once screen 2 lets its game go, screen 3 may show it.
        library.releaseAll(from: 2)
        library.release(games[2], from: 3)
        var seen = Set<String>()
        for _ in 0 ..< 20 {
            let game = try #require(library.pick(for: 3, allowsDirect: true))
            seen.insert(game.identity)
            library.release(game.identity, from: 3)
        }
        #expect(!seen.contains(games[0]))
        #expect(seen.contains(games[1]))
    }

    /// As a screen plays: its next game is picked while its current one is still on it.
    @Test(arguments: [2, 3, 10, 50, 150])
    func aScreenNeverShowsAGameTwiceInARow(count: Int) throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        try writePlaylist(count, to: url)
        let log = RecordingLog()
        let library = GameLibrary(playlist: PlaylistStore(url: url, log: log), direct: nil, ownGame: ownGame, log: log,
                                  generator: SeededGenerator(seed: 11))
        var current = try #require(library.pick(for: 1, allowsDirect: true)).identity
        var seen: Set<String> = [current]
        for _ in 0 ..< 300 {
            let next = try #require(library.pick(for: 1, allowsDirect: true)).identity
            #expect(next != current)
            library.release(current, from: 1)
            current = next
            seen.insert(next)
        }
        #expect(seen.count == count)
    }

    @Test func aScreenNeverShowsAGameTwiceInARowInDirectMode() throws {
        let folder = try TemporaryFolder()
        let log = RecordingLog()
        let paths = (0 ..< 3).map { "/Volumes/Disk/game \($0).sgf" }
        let library = GameLibrary(playlist: PlaylistStore(url: folder.url.appendingPathComponent("none"), log: log),
                                  direct: Self.direct(paths, log: log), ownGame: ownGame, log: log,
                                  generator: SeededGenerator(seed: 11))
        var current = try #require(library.pick(for: 1, allowsDirect: true))
        for _ in 0 ..< 100 {
            let next = try #require(library.pick(for: 1, allowsDirect: true))
            #expect(next.source == .direct)
            #expect(next.identity != current.identity)
            library.release(current.identity, from: 1)
            current = next
        }
    }

    @Test func avoidsFewerRecentGamesBeforeAScreensOwn() {
        let recent = (0 ..< 300).map { "game \($0)" }
        let avoided = GameLibrary.avoided(others: ["other"], own: ["game 299"], recent: recent)
        #expect(avoided.map(\.count) == [201, 101, 51, 26, 13, 7, 4, 2, 2, 1])
        #expect(avoided.dropLast().allSatisfy { $0.isSuperset(of: ["other", "game 299"]) })
        #expect(avoided.last == ["other"])
        #expect(GameLibrary.avoided(others: [], own: [], recent: []) == [[], []])
    }

    @Test func noRepeatsAmongTheLast200() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        try writePlaylist(260, to: url)
        let log = RecordingLog()
        let library = GameLibrary(playlist: PlaylistStore(url: url, log: log), direct: nil, ownGame: ownGame, log: log,
                                  generator: SeededGenerator(seed: 2))
        var shown: [String] = []
        for _ in 0 ..< 400 {
            let game = try #require(library.pick(for: 1, allowsDirect: true))
            #expect(!shown.suffix(GameLibrary.recentLimit).contains(game.identity))
            shown.append(game.identity)
            library.release(game.identity, from: 1)
        }
    }

    @Test func readsThePlaylistAgainWhenItIsReplaced() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        try writePlaylist(5, prefix: "old", to: url)
        let log = RecordingLog()
        let store = PlaylistStore(url: url, log: log)
        let library = GameLibrary(playlist: store, direct: nil, ownGame: ownGame, log: log)
        #expect(try #require(library.pick(for: 1, allowsDirect: true)).identity.contains("old"))
        #expect(try #require(library.pick(for: 1, allowsDirect: true)).identity.contains("old"))
        #expect(log.messages(.playlist, level: .notice).count { $0.hasPrefix("Read the playlist") } == 1)

        try writePlaylist(7, prefix: "new", to: url)
        #expect(try #require(library.pick(for: 1, allowsDirect: true)).identity.contains("new"))
        #expect(store.count == 7)
        #expect(log.messages(.playlist, level: .notice).count { $0.hasPrefix("Read the playlist") } == 2)

        // Renamed away, as John's test of direct mode does: the next pick has no playlist.
        try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("off"))
        #expect(try #require(library.pick(for: 1, allowsDirect: true)).source == .own)
    }

    @Test func aPlaylistOfBadLinesCountsAsNone() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        let bad = (0 ..< 30).map { "file:///Games/\($0).sgf\t(;GM[1]PB[Only One Player];B[aa])" }
        try Data(playlistText(bad).utf8).write(to: url)
        let log = RecordingLog()
        let store = PlaylistStore(url: url, log: log)
        let library = GameLibrary(playlist: store, direct: nil, ownGame: ownGame, log: log)
        #expect(try #require(library.pick(for: 1, allowsDirect: true)).source == .own)
        #expect(store.state == .noPlayableLine)
        #expect(log.messages(.playlist).count { $0.hasSuffix("skipped: no game that qualifies") } == PlaylistStore.badLinesLimit)
    }

    @Test(arguments: [
        ("# SGF Tools screensaver games\n# format: 2\n", PlaylistStore.State.unsupportedFormat("2")),
        ("Some other file\n", .notAPlaylist),
        ("# SGF Tools screensaver games\n# format: 1\n# games: 0\n", .noPlayableLine),
    ])
    func aPlaylistThatCannotBeUsed(text: String, state: PlaylistStore.State) throws {
        let folder = try TemporaryFolder()
        let path = try folder.write(text, to: "playlist")
        let store = PlaylistStore(url: URL(fileURLWithPath: path), log: RecordingLog())
        #expect(!store.refresh())
        #expect(store.state == state)
    }

    @Test func aPlaylistTheHostMayNotRead() throws {
        var reader = GameFileReader()
        reader.status = { _ in .failure(.init(code: EPERM)) }
        let log = RecordingLog()
        let store = PlaylistStore(url: URL(fileURLWithPath: "/Users/tester/Library/playlist"), reader: reader, log: log)
        #expect(!store.refresh())
        #expect(store.state == .refused)
        #expect(log.messages(.playlist) == ["The playlist can't be read: refused (EPERM)"])
    }

    /// Found, but not opened: read again at each pick, and logged once.
    @Test func aPlaylistTheHostMayNotOpenIsLoggedOnce() {
        var reader = GameFileReader()
        reader.status = { _ in .success(.init(inode: 1, size: 100, modified: [0, 0], isDataless: false)) }
        let reads = Counter()
        reader.readPrefix = { _, _ in
            reads.increment()
            return .failure(.init(code: EPERM))
        }
        let log = RecordingLog()
        let store = PlaylistStore(url: URL(fileURLWithPath: "/Users/tester/Library/playlist"), reader: reader, log: log)
        for _ in 0 ..< 5 { #expect(!store.refresh()) }
        #expect(store.state == .refused)
        #expect(reads.value == 5)
        #expect(log.messages(.playlist) == ["The playlist can't be read: refused (EPERM)"])
    }
}

@Suite("Screensaver: direct mode")
struct ScreensaverDirectModeTests {
    static let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    static func source(_ paths: [String], log: RecordingLog, reader: GameFileReader = scriptedReader(),
                       limits: DirectSource.Limits = .init(), volumes: [LocationClass] = [],
                       clock: @escaping @Sendable () -> Double = { 0 }, queries: Counter? = nil) -> DirectSource {
        DirectSource(query: { queries?.increment(); return paths }, reader: reader, home: home, volumes: { volumes },
                     limits: limits, log: log, clock: clock)
    }

    @Test func twoDeniedReadsDenyALocationButMissingFilesDont() {
        let log = RecordingLog()
        let paths = (0 ..< 10).map { "/Users/tester/Documents/denied \($0).sgf" }
            + (0 ..< 10).map { "/Volumes/Disk/gone \($0).sgf" }
        let source = Self.source(paths, log: log)
        var generator = SeededGenerator(seed: 1)
        #expect(source.pick(avoiding: [], using: &generator) == nil)
        #expect(source.health(of: .documents) == .denied)
        #expect(source.health(of: .volume("Disk")) == .ok)
        #expect(source.reasonGivenUp == "20 failed picks in a row")
        let denial = log.messages(.direct, level: .notice).first { $0.hasPrefix("Documents denied") }
        #expect(denial == "Documents denied: 2 reads refused (EPERM); reading it needs Files & Folders: Documents Folder for legacyScreenSaver")
        // Once denied, Documents is never read again.
        let documentReads = log.messages(.direct, level: .info).count { $0.hasPrefix("Documents:") }
        #expect(documentReads == 2)
    }

    @Test func aGameComesBackAndResetsTheFailures() throws {
        let log = RecordingLog()
        let paths = ["/Users/tester/Documents/denied.sgf", "/Volumes/Disk/problem.sgf", "/Volumes/Disk/game.sgf"]
        let source = Self.source(paths, log: log)
        var generator = SeededGenerator(seed: 3)
        for _ in 0 ..< 10 {
            let game = try #require(source.pick(avoiding: [], using: &generator))
            #expect(game.source == .direct)
            #expect(game.identity == "file:///Volumes/Disk/game.sgf")
        }
        #expect(source.reasonGivenUp == nil)
    }

    @Test func avoidsTheGamesItIsAskedTo() throws {
        let log = RecordingLog()
        let paths = (0 ..< 4).map { "/Volumes/Disk/game \($0).sgf" }
        let source = Self.source(paths, log: log)
        var generator = SeededGenerator(seed: 3)
        let avoid = Set(paths.dropLast().map(DirectSource.identity(of:)))
        for _ in 0 ..< 10 {
            #expect(try #require(source.pick(avoiding: [avoid], using: &generator)).identity == "file:///Volumes/Disk/game%203.sgf")
        }
    }

    @Test func fiveUnreadableFilesSkipALocation() {
        let log = RecordingLog()
        let paths = (0 ..< 10).map { "/Users/tester/Downloads/locked \($0).sgf" }
        let source = Self.source(paths, log: log)
        var generator = SeededGenerator(seed: 1)
        #expect(source.pick(avoiding: [], using: &generator) == nil)
        #expect(source.health(of: .downloads) == .skipped)
        #expect(source.reasonGivenUp == "every location is denied or skipped")
        #expect(log.messages(.direct, level: .info).count == 5)
    }

    @Test func timeOutsDenyALocationAndALateGameClearsIt() async throws {
        let log = RecordingLog()
        let release = DispatchSemaphore(value: 0)
        let paths = (0 ..< 5).map { "/Users/tester/Documents/slow \($0).sgf" } + ["/Volumes/Disk/problem.sgf"]
        var limits = DirectSource.Limits()
        limits.readTimeout = 0.05
        limits.blockedReads = 10
        limits.failedPicksInARow = 12
        let source = Self.source(paths, log: log, reader: scriptedReader(release: release), limits: limits)
        var generator = SeededGenerator(seed: 5)
        #expect(source.pick(avoiding: [], using: &generator) == nil)
        #expect(source.health(of: .documents) == .denied)
        #expect(log.messages(.direct, level: .notice).contains { $0.hasPrefix("Documents denied: 3 time-outs in a row") })
        #expect(log.messages(.direct, level: .info).count { $0.contains("timed out") } == 3)

        // macOS answers at last, and the reads come back with games.
        for _ in 0 ..< 3 { release.signal() }
        for _ in 0 ..< 200 where source.health(of: .documents) != .ok {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(source.health(of: .documents) == .ok)
        #expect(log.messages(.direct, level: .notice).contains("Documents may be read again"))
    }

    @Test func sixReadsThatDontComeBackGiveUp() {
        let log = RecordingLog()
        let release = DispatchSemaphore(value: 0)
        defer { for _ in 0 ..< 6 { release.signal() } }
        let paths = (0 ..< 3).map { "/Users/tester/Documents/slow \($0).sgf" } + (0 ..< 3).map { "/Volumes/Disk/slow \($0).sgf" }
        var limits = DirectSource.Limits()
        limits.readTimeout = 0.05
        limits.timeoutsInARow = 10
        let source = Self.source(paths, log: log, reader: scriptedReader(release: release), limits: limits)
        var generator = SeededGenerator(seed: 2)
        #expect(source.pick(avoiding: [], using: &generator) == nil)
        #expect(source.reasonGivenUp == "6 abandoned reads haven't come back")
    }

    /// A location whose reads never come back is denied, and the others still give games.
    @Test func aBlockedLocationIsDeniedAndTheOthersStillPlay() throws {
        let log = RecordingLog()
        let release = DispatchSemaphore(value: 0)
        defer { for _ in 0 ..< 3 { release.signal() } }
        let paths = (0 ..< 50).map { "/Volumes/Disk/slow \($0).sgf" } + (0 ..< 50).map { "/Users/tester/Documents/game \($0).sgf" }
        var limits = DirectSource.Limits()
        limits.readTimeout = 0.05
        let source = Self.source(paths, log: log, reader: scriptedReader(release: release), limits: limits)
        var generator = SeededGenerator(seed: 6)
        for _ in 0 ..< 30 {
            let game = try #require(source.pick(avoiding: [], using: &generator))
            #expect(game.identity.hasPrefix("file:///Users/tester/Documents/"))
        }
        #expect(source.health(of: .volume("Disk")) == .denied)
        #expect(source.health(of: .documents) == .ok)
        #expect(source.reasonGivenUp == nil)
        #expect(log.messages(.direct, level: .info).count { $0.contains("timed out") } == 3)
    }

    /// Reads that time out but come back later, as on a disk that takes a while to wake, hold no
    /// thread once they're back, so however many there are, direct mode goes on.
    @Test func readsThatComeBackLateNoLongerCount() async throws {
        let log = RecordingLog()
        let release = DispatchSemaphore(value: 0)
        let paths = (0 ..< 3).map { "/Volumes/Disk/slow \($0).sgf" } + (0 ..< 7).map { "/Volumes/Disk/game \($0).sgf" }
        var limits = DirectSource.Limits()
        limits.readTimeout = 0.02
        limits.timeoutsInARow = 100
        let source = Self.source(paths, log: log, reader: scriptedReader(release: release), limits: limits)
        var generator = SeededGenerator(seed: 4)
        var released = 0
        for _ in 0 ..< 40 {
            #expect(source.pick(avoiding: [], using: &generator) != nil)
            // macOS answers each read that timed out before the next pick.
            let timedOut = log.messages(.direct, level: .info).count { $0.contains("timed out") }
            while released < timedOut {
                release.signal()
                released += 1
            }
            for _ in 0 ..< 200 where log.messages(.direct, level: .notice).count(where: { $0.contains("came back") }) < timedOut {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        #expect(released > limits.blockedReads)
        #expect(source.reasonGivenUp == nil)
    }

    @Test func anIdentityIsMadeWithoutLookingAtTheDisk() throws {
        let folder = try TemporaryFolder()
        let directory = folder.url.appendingPathComponent("x.sgf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(DirectSource.identity(of: directory.path).hasSuffix("/x.sgf"))
    }

    @Test func aQueryThatFailsOrTakesTooLongGivesUp() {
        struct Failure: Error {}
        let log = RecordingLog()
        let failing = DirectSource(query: { throw Failure() }, reader: scriptedReader(), home: Self.home, volumes: { [] },
                                   log: log)
        var generator = SeededGenerator(seed: 1)
        #expect(failing.pick(avoiding: [], using: &generator) == nil)
        #expect(failing.reasonGivenUp == "the Spotlight query failed: Failure()")

        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var limits = DirectSource.Limits()
        limits.queryTimeout = 0.05
        let slow = DirectSource(query: { release.wait(); return [] }, reader: scriptedReader(), home: Self.home,
                                volumes: { [] }, limits: limits, log: log)
        #expect(slow.pick(avoiding: [], using: &generator) == nil)
        #expect(slow.reasonGivenUp == "the Spotlight query took more than 0.05 s")

        let empty = Self.source([], log: log)
        #expect(empty.pick(avoiding: [], using: &generator) == nil)
        #expect(empty.reasonGivenUp == "Spotlight found no games")
    }

    @Test func asksSpotlightAgainInALaterSessionAfterAnHour() throws {
        let log = RecordingLog()
        let queries = Counter()
        let now = Counter()
        let source = Self.source(["/Volumes/Disk/a.sgf"], log: log, clock: { Double(now.value) * 1800 }, queries: queries)
        var generator = SeededGenerator(seed: 1)
        _ = try #require(source.pick(avoiding: [], using: &generator))
        now.increment()
        source.sessionDidStart()
        _ = try #require(source.pick(avoiding: [], using: &generator))
        #expect(queries.value == 1, "half an hour: the list is kept")
        now.increment()
        _ = try #require(source.pick(avoiding: [], using: &generator))
        #expect(queries.value == 1, "an hour, but in the same session")
        source.sessionDidStart()
        _ = try #require(source.pick(avoiding: [], using: &generator))
        #expect(queries.value == 2)
    }

    @Test func logsACountForEveryVolumeEvenWhenItIsZero() throws {
        let log = RecordingLog()
        let paths = ["/Users/tester/Documents/a.sgf", "/Volumes/Disk/b.sgf", "/Users/tester/Library/Containers/c.sgf"]
        let source = Self.source(paths, log: log, volumes: [.volume("Disk"), .volume("Empty Disk")])
        var generator = SeededGenerator(seed: 1)
        _ = try #require(source.pick(avoiding: [], using: &generator))
        let notices = log.messages(.direct, level: .notice)
        #expect(notices.first?.hasPrefix("Spotlight found 3 games in ") == true)
        #expect(Array(notices.dropFirst().prefix(4)) == [
            "Documents: 1", "the volume Disk: 1", "the volume Empty Disk: 0", "Left out, ~/Library: 1",
        ])
        // Each read's path is logged privately, apart from the message.
        let read = try #require(log.lines.first { $0.category == .direct && $0.level == .info })
        #expect(read.path?.hasSuffix(".sgf") == true)
        #expect(!read.message.contains("/"))
    }
}
