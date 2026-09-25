import Darwin
import Foundation
import SGFKit

/// Reads one candidate file for the screensaver, and says what happened in a way that callers can
/// tally by location (see `docs/screensaver.md`, 1.7).
///
/// It checks the file with `stat` first, which the sandbox allows everywhere, then reads at most
/// ``byteLimit`` bytes with a plain `read`. It never maps the file: a mapped file on a volume that
/// goes away raises SIGBUS, which would crash the screensaver's host.
struct GameFileReader: Sendable {
    /// What reading a file came to.
    enum Outcome: Sendable {
        /// The file's first game qualifies (see ``Playlist/isGame(_:)``).
        case game(SGFGame)
        /// The file isn't there (`ENOENT`): Spotlight's index is stale.
        case missing
        /// A cloud file whose data isn't on the Mac (`SF_DATALESS`). Reading it would download
        /// it, so it is never read.
        case dataless
        /// The file parses but its first game doesn't qualify: it changed since it was indexed.
        case notAGame
        /// Refused by macOS's privacy settings (`EPERM`), since the sandbox itself allows reading.
        case denied
        /// Refused by the file's own permissions (`EACCES`), or another error, with its code.
        case unreadable(Int32)

        /// A short name for logs and tallies.
        var name: String {
            switch self {
            case .game: "game"
            case .missing: "missing"
            case .dataless: "dataless"
            case .notAGame: "not a game"
            case .denied: "denied"
            case .unreadable(let code): code == EACCES ? "unreadable" : "unreadable (errno \(code))"
            }
        }

        /// The outcome of a failed `stat`, `open`, or `read`, by its `errno`.
        init(errorCode code: Int32) {
            switch code {
            case ENOENT, ENOTDIR: self = .missing
            case EPERM: self = .denied
            default: self = .unreadable(code)
            }
        }
    }

    /// What a read came to, and how much it read.
    struct Result: Sendable {
        let outcome: Outcome
        let bytesRead: Int
    }

    /// What `stat` says about a file.
    struct FileStatus: Sendable, Equatable {
        let inode: UInt64
        let size: Int
        /// The modification date, as seconds and nanoseconds since 1970.
        let modified: [Int]
        let isDataless: Bool
    }

    /// A failed system call's `errno`.
    struct FileError: Error, Equatable {
        let code: Int32
    }

    /// The most of a file that is read: 2 MB, as for Spotlight and the preview.
    static let byteLimit = 2 << 20

    var byteLimit = Self.byteLimit

    /// Gets a file's status; replaced by the tests.
    var status: @Sendable (String) -> Swift.Result<FileStatus, FileError> = Self.status(ofFileAt:)

    /// Reads up to a number of bytes from the start of a file; replaced by the tests.
    var readPrefix: @Sendable (String, Int) -> Swift.Result<Data, FileError> = Self.readPrefix(ofFileAt:limit:)

    /// Reads a file's first game.
    func read(_ path: String) -> Result {
        switch status(path) {
        case .failure(let error):
            return Result(outcome: Outcome(errorCode: error.code), bytesRead: 0)
        case .success(let status) where status.isDataless:
            return Result(outcome: .dataless, bytesRead: 0)
        case .success:
            break
        }
        switch readPrefix(path, byteLimit) {
        case .failure(let error):
            return Result(outcome: Outcome(errorCode: error.code), bytesRead: 0)
        case .success(let data):
            let collection = SGFParser.parse(data, options: .init(stopAfterFirstGame: true))
            guard let game = collection.games.first, Playlist.isGame(GameInfo(game: game)) else {
                return Result(outcome: .notAGame, bytesRead: data.count)
            }
            return Result(outcome: .game(game), bytesRead: data.count)
        }
    }

    // MARK: - System calls

    /// A file's status from `stat`.
    static func status(ofFileAt path: String) -> Swift.Result<FileStatus, FileError> {
        var info = stat()
        guard stat(path, &info) == 0 else { return .failure(FileError(code: errno)) }
        return .success(FileStatus(
            inode: UInt64(info.st_ino), size: Int(info.st_size),
            modified: [Int(info.st_mtimespec.tv_sec), Int(info.st_mtimespec.tv_nsec)],
            isDataless: info.st_flags & UInt32(SF_DATALESS) != 0
        ))
    }

    /// Reads up to `limit` bytes from the start of a file with `open` and `read`, never mapping
    /// it.
    static func readPrefix(ofFileAt path: String, limit: Int) -> Swift.Result<Data, FileError> {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return .failure(FileError(code: errno)) }
        defer { close(descriptor) }
        var info = stat()
        let size = fstat(descriptor, &info) == 0 ? Int(info.st_size) : limit
        let capacity = max(0, min(limit, size))
        guard capacity > 0 else { return .success(Data()) }
        var data = Data(count: capacity)
        var filled = 0
        var failure: Int32?
        data.withUnsafeMutableBytes { buffer in
            let base = buffer.baseAddress!
            while filled < capacity {
                let count = Darwin.read(descriptor, base + filled, capacity - filled)
                if count > 0 {
                    filled += count
                } else if count == 0 {
                    break
                } else if errno != EINTR {
                    failure = errno
                    break
                }
            }
        }
        if let failure { return .failure(FileError(code: failure)) }
        data.count = filled
        return .success(data)
    }
}
