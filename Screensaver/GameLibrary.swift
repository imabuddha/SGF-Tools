import Dispatch
import Foundation
import Synchronization

/// The games every screen plays, one library per process (see `docs/screensaver.md`, 1.8).
///
/// For each new game it goes down this list, logging each step:
/// 1. **The playlist** the app wrote.
/// 2. **Direct mode**, never in a preview: Spotlight, and the files themselves.
/// 3. **The screensaver's own game**, with a hint to open SGF Tools.
///
/// For every screen, a pick avoids the games on the other screens and the last 200 shown, as far
/// as the source can. Picks run one at a time on the library's queue, off the main thread, since
/// a pick may read a file.
final class GameLibrary: @unchecked Sendable {
    /// The number of recent games a pick avoids.
    static let recentLimit = 200

    /// What the screens are showing, which picks on any thread may read.
    private struct Shown {
        /// The games each screen holds: the one playing, and the next one while it's prepared.
        var onScreen: [Int: [String]] = [:]
        /// The games shown most recently, oldest first.
        var recent: [String] = []
    }

    private let queue = DispatchQueue(label: "com.pragmaphilia.SGFTools.Screensaver.library", qos: .utility)
    private let playlist: PlaylistStore?
    private let direct: DirectSource?
    private let ownGame: @Sendable () -> SaverGame?
    private let log: any SaverLogging
    private let shown = Mutex(Shown())
    /// Used only by picks, which run one at a time.
    private var generator: any RandomNumberGenerator

    /// A library of the given sources. The tests give their own; the screensaver's are those of
    /// ``init(bundle:)``.
    init(playlist: PlaylistStore?, direct: DirectSource?, ownGame: @escaping @Sendable () -> SaverGame?,
         log: any SaverLogging, generator: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.playlist = playlist
        self.direct = direct
        self.ownGame = ownGame
        self.log = log
        self.generator = generator
    }

    /// The screensaver's library: the playlist in the real `~/Library/Application Support/SGF
    /// Tools`, direct mode, and the own game from the screensaver's bundle.
    convenience init(bundle: Bundle) {
        let log = SaverLog.shared
        self.init(playlist: PlaylistStore(log: log), direct: DirectSource(log: log),
                  ownGame: { SaverGame.own(in: bundle) }, log: log)
    }

    /// Picks a game for a screen, on the library's queue, and hands it to `completion` there.
    func requestGame(for screen: Int, allowsDirect: Bool, completion: @escaping @Sendable (SaverGame?) -> Void) {
        queue.async {
            completion(self.pick(for: screen, allowsDirect: allowsDirect))
        }
    }

    /// Picks a game for a screen, on the caller's thread: from the playlist, then direct mode if
    /// it's allowed, then the own game. The game counts as on the screen until it is released.
    /// Views go through ``requestGame(for:allowsDirect:completion:)``; the tests call this.
    func pick(for screen: Int, allowsDirect: Bool) -> SaverGame? {
        let (others, recent, isFirst) = shown.withLock { shown in
            let others = Set(shown.onScreen.filter { $0.key != screen }.values.joined())
            return (others, Set(shown.recent), shown.onScreen.values.allSatisfy(\.isEmpty))
        }
        if isFirst { direct?.sessionDidStart() }
        let avoided = [others.union(recent), others]

        var game: SaverGame?
        if let playlist {
            if playlist.refresh() {
                game = pick { playlist.pick(avoiding: avoided, using: &$0) }
                if game == nil { log.notice(.playlist, "Screen \(screen): no game from the playlist (\(playlist.state))") }
            } else {
                log.info(.playlist, "Screen \(screen): no playlist to pick from (\(playlist.state))")
            }
        }
        if game == nil, let direct {
            if !allowsDirect {
                log.info(.direct, "Screen \(screen): a preview, so no direct mode")
            } else if let reason = direct.reasonGivenUp {
                log.info(.direct, "Screen \(screen): direct mode has given up (\(reason))")
            } else {
                game = pick { direct.pick(avoiding: avoided, using: &$0) }
            }
        }
        if game == nil {
            game = ownGame()
            if game == nil { log.error(.play, "Screen \(screen): the screensaver's own game can't be read") }
        }
        guard let game else { return nil }
        shown.withLock { shown in
            shown.onScreen[screen, default: []].append(game.identity)
            shown.recent.append(game.identity)
            if shown.recent.count > Self.recentLimit { shown.recent.removeFirst(shown.recent.count - Self.recentLimit) }
        }
        log.info(.play, "Screen \(screen): picked a game from the \(game.source.rawValue)", path: game.identity)
        return game
    }

    /// A screen has finished with a game.
    func release(_ identity: String, from screen: Int) {
        shown.withLock { shown in
            guard let index = shown.onScreen[screen]?.firstIndex(of: identity) else { return }
            shown.onScreen[screen]?.remove(at: index)
        }
    }

    /// A screen has stopped: it holds no games.
    func releaseAll(from screen: Int) {
        shown.withLock { _ = $0.onScreen.removeValue(forKey: screen) }
    }

    /// Runs a source's pick with the library's generator.
    private func pick(_ body: (inout AnyGenerator) -> SaverGame?) -> SaverGame? {
        var wrapped = AnyGenerator(base: generator)
        defer { generator = wrapped.base }
        return body(&wrapped)
    }
}

/// Any random number generator, as a concrete type that generic code can take `inout`.
struct AnyGenerator: RandomNumberGenerator {
    var base: any RandomNumberGenerator

    mutating func next() -> UInt64 {
        base.next()
    }
}
