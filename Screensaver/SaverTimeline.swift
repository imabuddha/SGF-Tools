import Foundation

/// What one screen shows at each moment of a game (see `docs/screensaver.md`, section 4).
///
/// A pure function of the time since the game started, so late or irregular ticks never make
/// the moves drift. With N the number of moves played:
///
/// | Time (s) | What happens |
/// |---|---|
/// | 0 | The board starts fading in (2 s), with the position before move 1 |
/// | 0.75 | The details start fading in (1.5 s) |
/// | 3 | Move 1 |
/// | 3 + (n − 1) | Move n, one a second, to move N |
/// | N + 7 | After the last position has held for 5 s, the board and details fade out (2 s) |
/// | N + 9 | Black for 1 s |
/// | N + 10 | The game is over, and the next one starts |
///
/// The times come from ``Look``.
struct SaverTimeline: Sendable, Equatable {
    /// What is shown at a moment. The fades themselves are animations from one state to the next.
    struct State: Sendable, Equatable {
        /// The number of moves on the board.
        var movesShown: Int
        /// Whether the board and details are fading in or shown, rather than fading out or gone.
        var showsGame: Bool
        /// Whether the details are fading in or shown.
        var showsDetails: Bool
        /// Whether the game is over.
        var isOver: Bool
    }

    /// The number of moves played: the game's first moves, as many as ``Playlist/moveLimit``,
    /// passes counted.
    let moveCount: Int

    init(moveCount: Int) {
        self.moveCount = max(0, moveCount)
    }

    /// When move `number` (from 1) is played.
    func time(ofMove number: Int) -> Double {
        Look.screensaverFirstMove + Double(number - 1) * Look.screensaverMoveInterval
    }

    /// When the board starts to fade out.
    var fadeOutStart: Double {
        (moveCount > 0 ? time(ofMove: moveCount) : Look.screensaverFadeIn) + Look.screensaverFinalHold
    }

    /// When the board has faded out.
    var fadeOutEnd: Double { fadeOutStart + Look.screensaverFadeOut }

    /// The length of the game, black pause included.
    var duration: Double { fadeOutEnd + Look.screensaverPause }

    /// When the details have faded in.
    var detailsFadeInEnd: Double { Look.screensaverDetailsDelay + Look.screensaverDetailsFadeIn }

    /// What is shown at a time since the game started. Before 0, nothing.
    func state(at time: Double) -> State {
        guard time >= 0 else { return State(movesShown: 0, showsGame: false, showsDetails: false, isOver: false) }
        let moves = time < Look.screensaverFirstMove
            ? 0
            : min(moveCount, Int(((time - Look.screensaverFirstMove) / Look.screensaverMoveInterval).rounded(.down)) + 1)
        return State(
            movesShown: moves,
            showsGame: time < fadeOutStart,
            showsDetails: time >= Look.screensaverDetailsDelay && time < fadeOutEnd,
            isOver: time >= duration
        )
    }

    /// The board's opacity at a time, from 0 to 1, as the fades make it. The details fade with
    /// it: they are drawn on top of the board's layer.
    func gameOpacity(at time: Double) -> Double {
        if time <= 0 || time >= fadeOutEnd { return 0 }
        if time < Look.screensaverFadeIn { return time / Look.screensaverFadeIn }
        if time < fadeOutStart { return 1 }
        return 1 - (time - fadeOutStart) / Look.screensaverFadeOut
    }

    /// The details' own opacity at a time, from 0 to 1, before the board's is applied.
    func detailsOpacity(at time: Double) -> Double {
        if time <= Look.screensaverDetailsDelay || time >= fadeOutEnd { return 0 }
        return min(1, (time - Look.screensaverDetailsDelay) / Look.screensaverDetailsFadeIn)
    }
}
