import Darwin
import Foundation
import SGFKit

/// The playlist as the screensaver reads it (see `docs/screensaver.md`, 1.8): read once, indexed,
/// and read again when the app replaces it. A pick parses only the line it chooses.
///
/// Not thread-safe: the game library uses it on its own queue.
final class PlaylistStore {
    /// What the last look at the file found.
    enum State: Equatable, CustomStringConvertible {
        case unread
        /// No playlist (`ENOENT`): the app hasn't made one.
        case missing
        /// Refused (`EPERM`), which would mean the real host isn't allowed what the probes were.
        case refused
        /// Another error, with its `errno`.
        case failed(Int32)
        /// Over ``sizeLimit``, with its size.
        case tooLarge(Int)
        case notAPlaylist
        case unsupportedFormat(String?)
        /// No line gave a game: the file has none, or ``badLinesLimit`` in a row were bad.
        case noPlayableLine
        case ready

        var description: String {
            switch self {
            case .unread: "not read yet"
            case .missing: "no playlist (ENOENT)"
            case .refused: "refused (EPERM)"
            case .failed(let code): "failed (errno \(code))"
            case .tooLarge(let size): "too large (\(size) bytes)"
            case .notAPlaylist: "not a playlist"
            case .unsupportedFormat(let format): "unsupported format \(format ?? "(none)")"
            case .noPlayableLine: "no playable line"
            case .ready: "ready"
            }
        }
    }

    /// The largest playlist read: 64 MB, more than six times what 10,000 games take.
    static let sizeLimit = 64 << 20

    /// After this many bad lines in a row, the playlist counts as having none.
    static let badLinesLimit = 20

    let url: URL
    private let reader: GameFileReader
    private let log: any SaverLogging
    private let now: @Sendable () -> Date

    private(set) var state = State.unread
    private var contents: Playlist.Contents?
    private var signature: GameFileReader.FileStatus?
    private var badLinesInARow = 0

    /// - Parameter reader: Supplies `stat` and the read, which the tests replace.
    init(url: URL = Playlist.defaultURL, reader: GameFileReader = GameFileReader(), log: any SaverLogging,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.reader = reader
        self.log = log
        self.now = now
    }

    /// Reads the playlist if it is new or has been replaced, comparing its inode, size, and
    /// modification date with what was read. Returns whether it has lines to pick from.
    @discardableResult
    func refresh() -> Bool {
        switch reader.status(url.path) {
        case .failure(let error):
            let failed: State = switch error.code {
            case ENOENT: .missing
            case EPERM: .refused
            default: .failed(error.code)
            }
            if failed != state { log.notice(.playlist, "The playlist can't be read: \(failed)") }
            state = failed
            contents = nil
            signature = nil
            return false
        case .success(let status):
            if status == signature { return state == .ready }
            read(status)
            return state == .ready
        }
    }

    /// The number of lines indexed.
    var count: Int { contents?.count ?? 0 }

    /// Picks a random line's game, avoiding the games in the first set it can, then the next.
    /// Lines that don't parse or don't qualify are skipped; after ``badLinesLimit`` of them in a
    /// row, the playlist counts as having none until it is replaced.
    func pick(avoiding avoided: [Set<String>], using generator: inout some RandomNumberGenerator) -> SaverGame? {
        guard state == .ready, let contents, contents.count > 0 else { return nil }
        for avoid in avoided + [[]] {
            for _ in 0 ..< 64 {
                let index = Int.random(in: 0 ..< contents.count, using: &generator)
                if let url = contents.url(at: index), avoid.contains(url) { continue }
                guard let entry = contents.entry(at: index),
                      let game = SaverGame(game: entry.game, source: .playlist, identity: entry.url)
                else {
                    badLinesInARow += 1
                    log.info(.playlist, "Line \(index + 1) skipped: no game that qualifies")
                    if badLinesInARow >= Self.badLinesLimit {
                        state = .noPlayableLine
                        log.notice(.playlist, "\(badLinesInARow) bad lines in a row: the playlist counts as having none")
                        return nil
                    }
                    continue
                }
                badLinesInARow = 0
                return game
            }
        }
        return nil
    }

    private func read(_ status: GameFileReader.FileStatus) {
        signature = status
        contents = nil
        badLinesInARow = 0
        guard status.size <= Self.sizeLimit else {
            state = .tooLarge(status.size)
            log.notice(.playlist, "The playlist is refused: \(status.size) bytes, over \(Self.sizeLimit)")
            return
        }
        let clock = ContinuousClock()
        let start = clock.now
        switch reader.readPrefix(url.path, Self.sizeLimit) {
        case .failure(let error):
            state = error.code == EPERM ? .refused : error.code == ENOENT ? .missing : .failed(error.code)
            signature = nil
            log.notice(.playlist, "The playlist can't be read: \(state)")
        case .success(let data):
            let readTime = clock.now - start
            do {
                let contents = try Playlist.Contents(data: data)
                let indexTime = clock.now - start - readTime
                self.contents = contents
                state = contents.count > 0 ? .ready : .noPlayableLine
                let age = now().timeIntervalSince(contents.header.made) / 86400
                log.notice(.playlist, """
                    Read the playlist: \(data.count) bytes, format \(Playlist.format), \
                    made \(contents.header.made.formatted(.iso8601)) (\(String(format: "%.1f", age)) days ago), \
                    \(contents.count) games of \(contents.header.found) found; \
                    read in \(Self.milliseconds(readTime)) ms, indexed in \(Self.milliseconds(indexTime)) ms
                    """)
            } catch {
                state = switch error {
                case .notAPlaylist: .notAPlaylist
                case .unsupportedFormat(let format): .unsupportedFormat(format)
                }
                log.notice(.playlist, "The playlist is refused: \(state)")
            }
        }
    }

    private static func milliseconds(_ duration: Duration) -> String {
        String(format: "%.1f", duration / .milliseconds(1))
    }
}
