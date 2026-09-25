import Darwin
import Foundation
import SGFKit
import Testing

@Suite("Playlist: reading a candidate file")
struct GameFileReaderTests {
    @Test func aGame() throws {
        let folder = try TemporaryFolder()
        let path = try folder.write(namedGame(), to: "game.sgf")
        let result = GameFileReader().read(path)
        guard case .game(let game) = result.outcome else {
            Issue.record("got \(result.outcome.name)")
            return
        }
        #expect(game.mainLineMoveCount == 60)
        #expect(result.bytesRead == namedGame().utf8.count)
    }

    @Test func aMissingFile() throws {
        let folder = try TemporaryFolder()
        let result = GameFileReader().read(folder.url.appendingPathComponent("gone.sgf").path)
        #expect(result.outcome.name == "missing")
        #expect(result.bytesRead == 0)
    }

    @Test func aFileOverTheLimitIsReadOnlyToIt() throws {
        let folder = try TemporaryFolder()
        let padding = String(repeating: "(;GM[1]SZ[9]C[padding];B[ee])\n", count: 90_000)
        let path = try folder.write(namedGame() + "\n" + padding, to: "large.sgf")
        #expect(try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? 0 > GameFileReader.byteLimit)
        let result = GameFileReader().read(path)
        #expect(result.outcome.name == "game")
        #expect(result.bytesRead == GameFileReader.byteLimit)
    }

    @Test func aFileCutOff() throws {
        let folder = try TemporaryFolder()
        let whole = namedGame(moves: 60)
        // Cut in the middle of move 40, and of move 10.
        let long = try folder.write(String(whole.prefix(whole.count - 6 * 20 - 3)), to: "cut.sgf")
        #expect(GameFileReader().read(long).outcome.name == "game")
        let short = try folder.write(String(whole.prefix(whole.count - 6 * 50 - 3)), to: "short.sgf")
        #expect(GameFileReader().read(short).outcome.name == "not a game")
    }

    @Test func aFileThatIsNotAGame() throws {
        let folder = try TemporaryFolder()
        let problem = try folder.write("(;GM[1]SZ[19]AB[dd][pd]AW[dp];B[pp])", to: "problem.sgf")
        #expect(GameFileReader().read(problem).outcome.name == "not a game")
        let empty = try folder.write("", to: "empty.sgf")
        #expect(GameFileReader().read(empty).outcome.name == "not a game")
    }

    @Test func aFileItsOwnPermissionsRefuse() throws {
        let folder = try TemporaryFolder()
        let path = try folder.write(namedGame(), to: "locked.sgf")
        #expect(chmod(path, 0) == 0)
        let result = GameFileReader().read(path)
        #expect(result.outcome.name == "unreadable")
        if case .unreadable(let code) = result.outcome { #expect(code == EACCES) }
    }

    private static let fileStatus = GameFileReader.FileStatus(inode: 1, size: 100, modified: [0, 0], isDataless: false)

    @Test func privacySettingsThatRefuseTheReadOrTheStat() {
        var reader = GameFileReader()
        reader.status = { _ in .success(Self.fileStatus) }
        reader.readPrefix = { _, _ in .failure(.init(code: EPERM)) }
        #expect(reader.read("/Users/tester/Documents/a.sgf").outcome.name == "denied")
        reader.status = { _ in .failure(.init(code: EPERM)) }
        #expect(reader.read("/Users/tester/Documents/a.sgf").outcome.name == "denied")
    }

    @Test func otherErrorsAreUnreadable() {
        var reader = GameFileReader()
        reader.status = { _ in .success(Self.fileStatus) }
        reader.readPrefix = { _, _ in .failure(.init(code: EACCES)) }
        #expect(reader.read("/a.sgf").outcome.name == "unreadable")
        reader.readPrefix = { _, _ in .failure(.init(code: EIO)) }
        #expect(reader.read("/a.sgf").outcome.name == "unreadable (errno \(EIO))")
        reader.status = { _ in .failure(.init(code: ENOENT)) }
        #expect(reader.read("/a.sgf").outcome.name == "missing")
    }

    @Test func aDatalessFileIsNeverRead() {
        let reads = Counter()
        var reader = GameFileReader()
        reader.status = { _ in .success(.init(inode: 1, size: 100, modified: [0, 0], isDataless: true)) }
        reader.readPrefix = { _, _ in
            reads.increment()
            return .success(Data())
        }
        #expect(reader.read("/Users/tester/Library/Mobile Documents/a.sgf").outcome.name == "dataless")
        #expect(reads.value == 0)
    }

    @Test func statusReportsTheInodeSizeAndDate() throws {
        let folder = try TemporaryFolder()
        let path = try folder.write("(;)", to: "a.sgf")
        let status = try GameFileReader.status(ofFileAt: path).get()
        #expect(status.size == 3)
        #expect(!status.isDataless)
        #expect(status.inode != 0)
    }
}

@Suite("Playlist: candidates from Spotlight")
struct GameCandidatesTests {
    static let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    @Test(arguments: [
        ("/Users/tester/Documents/Go/a.sgf", LocationClass.documents),
        ("/Users/tester/Desktop/a.sgf", .desktop),
        ("/Users/tester/Downloads/games/a.sgf", .downloads),
        ("/Users/tester/Go/a.sgf", .home),
        ("/Users/tester/DocumentsOld/a.sgf", .home),
        ("/Users/tester2/Documents/a.sgf", .startupDisk),
        ("/Users/Shared/a.sgf", .startupDisk),
        ("/opt/games/a.sgf", .startupDisk),
        ("/Volumes/Go Archive/Games/a.sgf", .volume("Go Archive")),
        ("/Volumes/USB/a.sgf", .volume("USB")),
    ])
    func locations(path: String, expected: LocationClass) {
        #expect(GameCandidates.location(of: path, home: Self.home.path) == expected)
        #expect(GameCandidates.exclusion(of: path, home: Self.home.path) == nil)
    }

    @Test(arguments: [
        ("/Users/tester/Library/Containers/com.example.go/Data/a.sgf", GameCandidates.Exclusion.library),
        ("/Users/tester/Library/Mobile Documents/com~apple~CloudDocs/a.sgf", .library),
        ("/Users/tester/.Trash/a.sgf", .trash),
        ("/Volumes/USB/.Trashes/501/a.sgf", .trash),
        ("/.Trashes/501/a.sgf", .trash),
        ("/Volumes/USB/.Spotlight-V100/Store/a.sgf", .spotlightStore),
        ("/.DocumentRevisions-V100/PerUID/501/a.sgf", .documentRevisions),
        ("/Volumes/USB/.DocumentRevisions-V100/a.sgf", .documentRevisions),
    ])
    func exclusions(path: String, expected: GameCandidates.Exclusion) {
        #expect(GameCandidates.exclusion(of: path, home: Self.home.path) == expected)
    }

    @Test func sortsPathsIntoCandidatesAndExclusions() {
        let paths = [
            "/Users/tester/Documents/a.sgf", "/Users/tester/Documents/b.sgf", "/Volumes/Disk/c.sgf",
            "/Users/tester/Library/Containers/x/d.sgf", "/Users/tester/.Trash/e.sgf", "/Volumes/Disk/.Trashes/f.sgf",
        ]
        let candidates = GameCandidates(paths: paths, home: Self.home)
        #expect(candidates.found == 6)
        #expect(candidates.candidates.map(\.path) == Array(paths.prefix(3)))
        #expect(candidates.excluded == [.library: 1, .trash: 2])
        #expect(candidates.countsByLocation == [.documents: 2, .volume("Disk"): 1])
    }

    @Test func theQueryNamesTheImportersAttributes() {
        let name = SpotlightAttributes.Name.self
        #expect(GameCandidates.query == """
            kMDItemContentType == "com.red-bean.sgf" && \(name.black) == "*" && \(name.white) == "*" && \
            \(name.moves) >= \(Playlist.minimumMoves)
            """)
    }

    /// The sandbox check's probe asks Spotlight the same question, from its own copy of the query.
    @Test func theSandboxChecksProbeAsksTheSameQuery() throws {
        let probe = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("SandboxCheck/probe.swift")
        let source = try String(contentsOf: probe, encoding: .utf8)
        #expect(source.contains("let query = #\"\(GameCandidates.query)\"#"))
    }
}
