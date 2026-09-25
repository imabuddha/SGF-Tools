import Foundation
import os

/// The screensaver's log categories (see `docs/screensaver.md`, section 9), under the subsystem
/// `com.pragmaphilia.SGFTools.Screensaver`.
enum SaverLogCategory: String, Sendable, CaseIterable {
    /// Loading, each view's life, the host's notifications, and playing and pausing.
    case lifecycle
    /// Once per process: the home folder the sandbox gives, and the real one.
    case environment
    /// Each read of the playlist, and lines skipped.
    case playlist
    /// Direct mode: the Spotlight query, the reads, and each location's health.
    case direct
    /// Each game: its screen, source, board size, moves, and drawing times.
    case play
}

/// How a line is logged. Notices are kept by the system, so `log show` finds them afterward;
/// info and debug lines only while `log stream --level info` (or `debug`) is running, or with
/// `log show --info`.
enum SaverLogLevel: Sendable {
    case error
    case notice
    case info
    case debug
}

/// Where the screensaver logs. The tests record the lines instead.
protocol SaverLogging: Sendable {
    /// Logs a line. The message is public, so it holds only what may be: counts, locations,
    /// volume names, error domains and codes, and timings. A file path goes in `path`, which is
    /// private.
    func log(_ level: SaverLogLevel, _ category: SaverLogCategory, _ message: String, path: String?)
}

extension SaverLogging {
    func error(_ category: SaverLogCategory, _ message: String, path: String? = nil) {
        log(.error, category, message, path: path)
    }

    func notice(_ category: SaverLogCategory, _ message: String, path: String? = nil) {
        log(.notice, category, message, path: path)
    }

    func info(_ category: SaverLogCategory, _ message: String, path: String? = nil) {
        log(.info, category, message, path: path)
    }

    func debug(_ category: SaverLogCategory, _ message: String, path: String? = nil) {
        log(.debug, category, message, path: path)
    }
}

/// The screensaver's unified log.
struct SaverLog: SaverLogging {
    static let subsystem = "com.pragmaphilia.SGFTools.Screensaver"

    static let shared = SaverLog()

    private let loggers: [SaverLogCategory: Logger] = Dictionary(
        uniqueKeysWithValues: SaverLogCategory.allCases.map { ($0, Logger(subsystem: SaverLog.subsystem, category: $0.rawValue)) }
    )

    func log(_ level: SaverLogLevel, _ category: SaverLogCategory, _ message: String, path: String?) {
        guard let logger = loggers[category] else { return }
        let type: OSLogType = switch level {
        case .error: .error
        case .notice: .default
        case .info: .info
        case .debug: .debug
        }
        if let path {
            logger.log(level: type, "\(message, privacy: .public) \(path, privacy: .private)")
        } else {
            logger.log(level: type, "\(message, privacy: .public)")
        }
    }
}
