import Darwin
import Foundation
import SGFKit
import Testing

@Suite("Playlist: the app's builder")
struct PlaylistBuilderTests {
    static let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    static let made = Date(timeIntervalSince1970: 1_790_000_000)

    /// A builder whose Spotlight answers `paths`, on a Mac with the volume Disk, and whose reads
    /// answer by path: a path with "denied", "locked", "gone", "cloud", or "problem" in it gives
    /// that outcome, and any other a game with 30 + its number of moves. Asked for access, it
    /// finds Documents and the volumes, and `access` answers for each place's path; it never
    /// reads the real Documents folder or volumes.
    static func builder(paths: [String], limit: Int = 10, volumes: [LocationClass] = [.volume("Disk")],
                        access: @escaping @Sendable (String) -> Int32? = { _ in nil }) -> PlaylistBuilder {
        var builder = PlaylistBuilder()
        builder.gameLimit = limit
        builder.home = home
        builder.findPaths = { paths }
        builder.mountedVolumes = { volumes }
        builder.now = { made }
        builder.reader = scriptedReader { path in 30 + (Int(path.filter(\.isNumber)) ?? 0) % 20 }
        builder.accessCheck.home = home
        builder.accessCheck.volumes = {
            volumes.compactMap { if case .volume(let name) = $0 { AccessCheck.Volume(name: name) } else { nil } }
        }
        builder.accessCheck.readTopLevel = access
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
            .build(writingTo: url, askingForAccess: false, using: &generator) { stage in
                guard case .choosing(let games, let wanted) = stage else { return }
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
            _ = try Self.builder(paths: paths, limit: 15).build(writingTo: url, askingForAccess: false, using: &generator)
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
            .build(writingTo: folder.url.appendingPathComponent("playlist"), askingForAccess: false, using: &generator)
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
        _ = try Self.builder(paths: Self.gamePaths(20), limit: 5).build(writingTo: url, askingForAccess: false, using: &generator)
        let before = try GameFileReader.status(ofFileAt: url.path).get()
        let old = try Data(contentsOf: url)
        _ = try Self.builder(paths: Self.gamePaths(20), limit: 8).build(writingTo: url, askingForAccess: false, using: &generator)
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
                                                             askingForAccess: false, using: &generator)
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
            try builder.build(writingTo: folder.url.appendingPathComponent("playlist"), askingForAccess: false, using: &generator)
        }
    }

    @Test func keepsThePlaylistWhenNoGameCanBeRead() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        var generator = SeededGenerator(seed: 1)
        _ = try Self.builder(paths: Self.gamePaths(12)).build(writingTo: url, askingForAccess: false, using: &generator)
        let before = try Data(contentsOf: url)
        let kept = PlaylistBuilder.KeptPlaylist(header: .init(made: Self.made, found: 12, games: 10), reason: .noGames)

        // Every read refused, as after Don't Allow.
        let denied = (0 ..< 12).map { "/Volumes/Disk/Games/denied \($0).sgf" }
        let report = try Self.builder(paths: denied).build(writingTo: url, askingForAccess: false, using: &generator)
        #expect(report.kept == kept)
        #expect(report.games == 0 && report.bytesWritten == 0)
        #expect(try Data(contentsOf: url) == before)

        // Nothing found, as when the only volume is away.
        #expect(try Self.builder(paths: []).build(writingTo: url, askingForAccess: false, using: &generator).kept == kept)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func keepsThePlaylistWhenSomeReadsAreRefused() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        var generator = SeededGenerator(seed: 2)
        _ = try Self.builder(paths: Self.gamePaths(12)).build(writingTo: url, askingForAccess: false, using: &generator)
        let paths = Self.gamePaths(3, in: "/Users/tester/Documents") + (0 ..< 9).map { "/Volumes/Disk/Games/denied \($0).sgf" }
        let report = try Self.builder(paths: paths).build(writingTo: url, askingForAccess: false, using: &generator)
        #expect(report.kept?.reason == .refused)
        #expect(report.games == 3)
        #expect(try Playlist.Contents(data: Data(contentsOf: url)).count == 10)
        let locale = Locale(identifier: "en_US")
        #expect(ScreensaverGames.describe(try #require(report.kept), games: report.games, locale: locale)
            == "Only 3 games could be read this time, so the games chosen before are kept.")
        #expect(ScreensaverGames.problems(in: report, locale: locale)
            == ["9 games in the volume Disk couldn’t be read: access not allowed"])
    }

    @Test func keepsThePlaylistWhileAVolumeWithItsGamesIsAway() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        var generator = SeededGenerator(seed: 3)
        _ = try Self.builder(paths: Self.gamePaths(12)).build(writingTo: url, askingForAccess: false, using: &generator)
        // With the volume away, Spotlight finds only what's in Documents.
        let documents = Self.gamePaths(4, in: "/Users/tester/Documents")
        let away = try Self.builder(paths: documents, volumes: [.volume("Other Disk")]).build(writingTo: url, askingForAccess: false, using: &generator)
        #expect(away.kept?.reason == .volumesMissing(["Disk"]))
        #expect(try Playlist.Contents(data: Data(contentsOf: url)).count == 10)
        #expect(ScreensaverGames.describe(try #require(away.kept), games: away.games, locale: Locale(identifier: "en_US"))
            == "The volume Disk isn’t connected, so the games chosen before are kept.")

        // With the volume back but nothing found on it, an update by itself can't tell whether
        // macOS hides the games or they're gone, and keeps them.
        let hidden = try Self.builder(paths: documents).build(writingTo: url, askingForAccess: false, using: &generator)
        #expect(hidden.kept?.reason == .hidden([.volume("Disk")]))
        #expect(try Playlist.Contents(data: Data(contentsOf: url)).count == 10)

        // With access to the volume, and the games gone from it, the smaller playlist replaces the
        // old.
        var back = Self.builder(paths: documents)
        let status = back.reader.status
        back.reader.status = { path in path.hasPrefix("/Volumes/Disk/") ? .failure(.init(code: ENOENT)) : status(path) }
        let gone = try back.build(writingTo: url, askingForAccess: true, using: &generator)
        #expect(gone.kept == nil)
        #expect(try Playlist.Contents(data: Data(contentsOf: url)).count == 4)
    }

    @Test func noGamesFoundStillWritesAPlaylist() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        var generator = SeededGenerator(seed: 1)
        let report = try Self.builder(paths: []).build(writingTo: url, askingForAccess: false, using: &generator)
        #expect(report.games == 0 && report.found == 0)
        #expect(try Playlist.Contents(data: Data(contentsOf: url)).count == 0)
    }

    // MARK: - Access

    @Test func anUpdateByItselfNeverAsksForAccess() throws {
        let folder = try TemporaryFolder()
        let reads = Counter()
        let stages = Recorder<PlaylistBuilder.Stage>()
        var generator = SeededGenerator(seed: 1)
        let report = try Self.builder(paths: Self.gamePaths(3), access: { _ in reads.increment(); return nil })
            .build(writingTo: folder.url.appendingPathComponent("playlist"), askingForAccess: false, using: &generator) {
                stages.append($0)
            }
        #expect(reads.value == 0)
        #expect(report.access == nil)
        #expect(stages.values.first == .askingSpotlight)
    }

    @Test func anUpdateFromTheButtonAsksAboutEachPlaceBeforeSpotlight() throws {
        let folder = try TemporaryFolder()
        let events = Recorder<String>()
        let stages = Recorder<PlaylistBuilder.Stage>()
        var builder = Self.builder(paths: Self.gamePaths(3), volumes: [.volume("Disk"), .volume("Archive")]) { path in
            events.append(path)
            return path.hasSuffix("Documents") ? EPERM : path.hasSuffix("Archive") ? ENOENT : nil
        }
        builder.findPaths = {
            events.append("Spotlight")
            return Self.gamePaths(3)
        }
        var generator = SeededGenerator(seed: 1)
        let report = try builder.build(writingTo: folder.url.appendingPathComponent("playlist"), askingForAccess: true,
                                       using: &generator) { stages.append($0) }
        #expect(events.values == ["/Users/tester/Documents", "/Volumes/Archive", "/Volumes/Disk", "Spotlight"])
        #expect(Array(stages.values.prefix(5)) == [
            .askingForAccess(.documents), .askingForAccess(.volume("Archive")), .askingForAccess(.volume("Disk")),
            .askingSpotlight, .choosing(games: 0, wanted: 3),
        ])
        #expect(report.access == [.documents: .denied, .volume("Archive"): .failed(ENOENT), .volume("Disk"): .allowed])
        #expect(report.deniedPlaces == [.documents])
        #expect(report.games == 3 && report.kept == nil)
    }

    /// **The guarantee:** no update, by itself or from the button, replaces a playlist with an
    /// empty one, or with a smaller one because macOS hid or refused files.
    @Test(arguments: [false, true])
    func neverReplacesAPlaylistWithAnEmptyOrAHiddenOne(askingForAccess: Bool) throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("playlist")
        var generator = SeededGenerator(seed: 4)
        _ = try Self.builder(paths: Self.gamePaths(12) + Self.gamePaths(4, in: "/Users/tester/Documents"), limit: 20)
            .build(writingTo: url, askingForAccess: false, using: &generator)
        let before = try Data(contentsOf: url)
        let reads = Counter()
        let denied: @Sendable (String) -> Int32? = { _ in reads.increment(); return EPERM }

        // Spotlight finds nothing: every place hidden, or refused at the button.
        let empty = try Self.builder(paths: [], access: denied).build(writingTo: url, askingForAccess: askingForAccess,
                                                                      using: &generator)
        #expect(empty.kept?.reason == .noGames)
        #expect(try Data(contentsOf: url) == before)

        // Spotlight finds only the games in the home folder: Documents and the volume hidden.
        let home = try Self.builder(paths: Self.gamePaths(3, in: "/Users/tester/Go"), access: denied)
            .build(writingTo: url, askingForAccess: askingForAccess, using: &generator)
        #expect(home.kept?.reason == .hidden([.documents, .volume("Disk")]))
        #expect(home.games == 3 && home.bytesWritten == 0)
        #expect(try Data(contentsOf: url) == before)
        #expect(reads.value == (askingForAccess ? 4 : 0), "Documents and Disk, twice, and only from the button")
    }
}

@Suite("Playlist: asking macOS for access")
struct AccessCheckTests {
    static let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    @Test func asksAboutDocumentsAndTheMacsOwnVolumes() {
        let volumes: [AccessCheck.Volume] = [
            .init(name: "Disk 10"),
            .init(name: "Server", isLocal: false),
            .init(name: "Recovery", isBrowsable: false),
            .init(name: ".timemachine"),
            .init(name: "Backups/Snapshot"),
            .init(name: "Macintosh HD", isRootFileSystem: true),
            .init(name: "Disk 9"),
            .init(name: "archive"),
        ]
        #expect(AccessCheck.places(home: Self.home, volumes: volumes) == [
            .init(location: .documents, path: "/Users/tester/Documents"),
            .init(location: .volume("archive"), path: "/Volumes/archive"),
            .init(location: .volume("Disk 9"), path: "/Volumes/Disk 9"),
            .init(location: .volume("Disk 10"), path: "/Volumes/Disk 10"),
        ])
        #expect(volumes.map(AccessCheck.reasonToLeaveOut) == [
            nil, "a network volume, which Spotlight doesn't search", "hidden", "hidden", "hidden", "the startup disk", nil, nil,
        ])
        #expect(AccessCheck.places(home: Self.home, volumes: []).map(\.location) == [.documents],
                "never Desktop or Downloads")
    }

    @Test func tellsARefusalFromOtherErrors() {
        var check = AccessCheck()
        check.home = Self.home
        check.volumes = { [.init(name: "Disk"), .init(name: "Gone"), .init(name: "Locked")] }
        check.readTopLevel = { path in
            switch path {
            case "/Users/tester/Documents": EPERM
            case "/Volumes/Gone": ENOENT
            case "/Volumes/Locked": EACCES
            default: nil
            }
        }
        let asked = Recorder<LocationClass>()
        let access = check.run { asked.append($0.location) }
        #expect(asked.values == [.documents, .volume("Disk"), .volume("Gone"), .volume("Locked")])
        #expect(access == [.documents: .denied, .volume("Disk"): .allowed, .volume("Gone"): .failed(ENOENT),
                           .volume("Locked"): .failed(EACCES)])
    }

    /// The real read, on folders in a temporary folder, which macOS's privacy settings don't guard.
    @Test func readsAFoldersTopLevel() throws {
        let folder = try TemporaryFolder()
        #expect(AccessCheck.readTopLevel(ofFolderAt: folder.url.path) == nil, "an empty folder")
        try folder.write("(;)", to: "a.sgf")
        #expect(AccessCheck.readTopLevel(ofFolderAt: folder.url.path) == nil)
        #expect(AccessCheck.readTopLevel(ofFolderAt: folder.url.appendingPathComponent("none").path) == ENOENT)
        let locked = folder.url.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        #expect(chmod(locked.path, 0o000) == 0)
        #expect(AccessCheck.readTopLevel(ofFolderAt: locked.path) == EACCES)
    }

    @Test func namesTheSettings() {
        #expect(LocationClass.documents.permission.description == "Files & Folders: Documents Folder")
        #expect(LocationClass.volume("Disk").permission.description == "Files & Folders: Removable Volumes")
        #expect(LocationClass.home.permission.description == "Full Disk Access")
        #expect([LocationClass.documents, .desktop, .downloads, .volume("Disk")].allSatisfy { $0.isGuarded })
        #expect(![LocationClass.home, .startupDisk].contains { $0.isGuarded })
        #expect(PrivacySetting.Pane.filesAndFolders.url.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
        #expect(PrivacySetting.Pane.fullDiskAccess.url.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }
}

@Suite("Playlist: keeping the games chosen before")
struct KeptPlaylistTests {
    static let home = "/Users/tester"

    /// A playlist of 6 games on the volume Disk, 4 in Documents, and 2 in the home folder.
    static func old() throws -> Playlist.Contents {
        let game = try game(namedGame(moves: 30))
        let paths = PlaylistBuilderTests.gamePaths(6) + PlaylistBuilderTests.gamePaths(4, in: "/Users/tester/Documents")
            + PlaylistBuilderTests.gamePaths(2, in: "/Users/tester/Go")
        let lines = paths.compactMap { Playlist.line(for: game, url: URL(fileURLWithPath: $0)) }
        return try Playlist.Contents(data: Data(playlistText(lines).utf8))
    }

    /// Whether to keep the old playlist when a new build found `found` games in each place and
    /// chose `games` of them.
    static func keep(games: Int, found: [LocationClass: Int], access: [LocationClass: AccessCheck.Access]?,
                     mounted: Set<LocationClass> = [.volume("Disk")], exists: (String) -> Bool = { _ in true })
        throws -> PlaylistBuilder.KeptPlaylist.Reason? {
        let tallies = found.mapValues { PlaylistBuilder.Tally(found: $0, read: $0, games: $0) }
        return try PlaylistBuilder.playlistToKeep(old(), games: games, tallies: tallies, access: access, mounted: mounted,
                                                  home: home, exists: exists)?.reason
    }

    @Test func keepsItWhenAGuardedPlaceMayBeHidden() throws {
        let homeOnly: [LocationClass: Int] = [.home: 5]
        // By itself: nothing looked at in the places, which macOS might ask about.
        let looked = Recorder<String>()
        #expect(try Self.keep(games: 5, found: homeOnly, access: nil, exists: { looked.append($0); return false })
            == .hidden([.documents, .volume("Disk")]))
        #expect(looked.values.isEmpty)
        // From the button, refused.
        #expect(try Self.keep(games: 5, found: homeOnly, access: [.documents: .denied, .volume("Disk"): .denied])
            == .hidden([.documents, .volume("Disk")]))
        // Allowed, but the games are still there: Spotlight hid them anyway.
        #expect(try Self.keep(games: 5, found: homeOnly, access: [.documents: .allowed, .volume("Disk"): .allowed])
            == .hidden([.documents, .volume("Disk")]))
        // Allowed, with only Documents' games gone.
        #expect(try Self.keep(games: 5, found: homeOnly, access: [.documents: .allowed, .volume("Disk"): .denied],
                              exists: { !$0.hasPrefix("/Users/tester/Documents/") })
            == .hidden([.volume("Disk")]))
    }

    @Test func replacesItWhenTheGamesAreGone() throws {
        let allowed: [LocationClass: AccessCheck.Access] = [.documents: .allowed, .volume("Disk"): .allowed]
        let looked = Recorder<String>()
        #expect(try Self.keep(games: 5, found: [.home: 5], access: allowed, exists: { looked.append($0); return false })
            == nil)
        #expect(looked.values.count == 10, "each old game in Documents and on Disk, up to 20 a place")
        // The home folder isn't guarded, so games gone from it are gone.
        #expect(try Self.keep(games: 10, found: [.documents: 4, .volume("Disk"): 6], access: nil) == nil)
        // A new playlist at least as large replaces it, whatever was hidden.
        #expect(try Self.keep(games: 12, found: [.home: 20], access: nil) == nil)
    }

    @Test func theOtherReasonsComeFirst() throws {
        #expect(try Self.keep(games: 0, found: [:], access: nil) == .noGames)
        #expect(try Self.keep(games: 5, found: [.home: 5], access: nil, mounted: []) == .volumesMissing(["Disk"]))
        var tallies: [LocationClass: PlaylistBuilder.Tally] = [.home: .init(found: 5, read: 5, games: 4)]
        tallies[.home]?.denied = 1
        #expect(try PlaylistBuilder.playlistToKeep(Self.old(), games: 4, tallies: tallies, access: nil,
                                                   mounted: [.volume("Disk")], home: Self.home) { _ in true }?.reason
            == .refused)
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

    // MARK: - Access

    static let byItself = """
        macOS hides the games SGF Tools isn’t allowed to read. Click Update Screensaver Games to let SGF Tools ask \
        for access to Documents and your other disks.
        """

    @Test func describesEachStage() {
        #expect(ScreensaverGames.describe(.askingForAccess(.documents)) == "Asking macOS for access to Documents…")
        #expect(ScreensaverGames.describe(.askingForAccess(.volume("Disk"))) == "Asking macOS for access to the volume Disk…")
        #expect(ScreensaverGames.describe(.askingSpotlight) == "Asking Spotlight for games…")
        #expect(ScreensaverGames.describe(.choosing(games: 2_345, wanted: 10_000), locale: Self.locale)
            == "Choosing games… 2,345 of 10,000")
    }

    @Test func saysWhyNoGamesWereFound() {
        var report = PlaylistBuilder.Report(made: Date(), found: 0, excluded: [:], tallies: [:], games: 0, bytesWritten: 93,
                                            seconds: 0.8)
        func describe() -> (status: String, problems: [String]) {
            ScreensaverGames.describe(report, now: Date(), locale: Self.locale, calendar: Self.calendar)
        }
        let noGames = "Spotlight found no games that name both players and have at least 20 moves."
        // By itself: it didn't ask.
        #expect(describe().status == noGames)
        #expect(describe().problems == [Self.byItself])
        // From the button, with every place refused.
        report.access = [.documents: .denied, .volume("Archive"): .denied, .volume("Disk"): .denied]
        #expect(describe().status == "Spotlight found no games that SGF Tools is allowed to read.")
        #expect(describe().problems == ["""
            SGF Tools isn’t allowed to read Documents, the volume Archive, or the volume Disk, so macOS hides the games \
            there. To allow it, turn on Documents Folder and Removable Volumes for SGF Tools in System Settings > \
            Privacy & Security > Files & Folders, then click Update Screensaver Games again.
            """])
        // From the button, with every place allowed: there are no games.
        report.access = [.documents: .allowed, .volume("Disk"): .failed(ENOENT)]
        #expect(describe().status == noGames)
        #expect(describe().problems.isEmpty)
    }

    @Test func saysWhyTheGamesChosenBeforeAreKept() throws {
        let made = try Date("2026-09-25T01:32:00Z", strategy: .iso8601)
        let header = Playlist.Header(made: made, found: 64_020, games: 10_000)
        var report = PlaylistBuilder.Report(
            made: made.addingTimeInterval(86_400), found: 441, excluded: [:],
            tallies: [.documents: .init(found: 441, read: 441, games: 441)], games: 441, bytesWritten: 0, seconds: 1,
            kept: .init(header: header, reason: .hidden([.volume("Archive")])))
        func describe() -> (status: String, problems: [String]) {
            ScreensaverGames.describe(report, now: made, locale: Self.locale, calendar: Self.calendar)
        }
        let kept = "Spotlight found no games in the volume Archive this time, so the games chosen before are kept."
        #expect(describe().status.replacingOccurrences(of: "\u{202F}", with: " ")
            == "10,000 games of 64,020, chosen today at 10:32 AM")
        #expect(describe().problems == [kept, Self.byItself])
        report.access = [.documents: .allowed, .volume("Archive"): .denied]
        #expect(describe().problems == [kept, """
            SGF Tools isn’t allowed to read the volume Archive, so macOS hides the games there. To allow it, turn on \
            Removable Volumes for SGF Tools in System Settings > Privacy & Security > Files & Folders, then click \
            Update Screensaver Games again.
            """])
        report.kept = .init(header: header, reason: .hidden([.documents, .volume("Archive")]))
        #expect(describe().problems.first
            == "Spotlight found no games in Documents or the volume Archive this time, so the games chosen before are kept.")
    }

    /// When the app opens, an update never asks for access, so macOS never puts up a request
    /// that nobody asked for; the button asks about each place.
    @MainActor
    @Test func onlyTheButtonAsksForAccess() async throws {
        let folder = try TemporaryFolder()
        let reads = Counter()
        let builder = PlaylistBuilderTests.builder(paths: []) { _ in
            reads.increment()
            return EPERM
        }
        let games = ScreensaverGames(playlistURL: folder.url.appendingPathComponent("playlist"), builder: builder)
        // As when the app opens with the screensaver installed and no playlist.
        games.show(nil, updatingIfStale: true)
        #expect(games.isUpdating)
        await withCheckedContinuation { done in games.afterUpdate { done.resume() } }
        #expect(reads.value == 0)
        #expect(games.settingsPane == nil)
        #expect(games.problems.count == 1)

        games.update()
        #expect(games.status == "Asking macOS for access…")
        await withCheckedContinuation { done in games.afterUpdate { done.resume() } }
        #expect(reads.value == 2, "Documents and the volume Disk")
        #expect(games.status == "Spotlight found no games that SGF Tools is allowed to read.")
        #expect(games.settingsPane == .filesAndFolders)
    }
}
