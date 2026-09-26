import Foundation
import Testing

@Suite("Screensaver: timeline")
struct ScreensaverTimelineTests {
    typealias State = SaverTimeline.State

    @Test func aFiftyMoveGame() {
        let timeline = SaverTimeline(moveCount: 50)
        #expect(Look.screensaverMoveInterval == 0.5 && Look.screensaverFinalHold == 10)
        #expect(timeline.duration == 40.5)
        #expect(timeline.fadeOutStart == 37.5)
        #expect(timeline.time(ofMove: 50) == 27.5)
        let expected: [(Double, State)] = [
            (-0.5, State(movesShown: 0, showsGame: false, showsDetails: false, isOver: false)),
            (0, State(movesShown: 0, showsGame: true, showsDetails: false, isOver: false)),
            (0.74, State(movesShown: 0, showsGame: true, showsDetails: false, isOver: false)),
            (0.75, State(movesShown: 0, showsGame: true, showsDetails: true, isOver: false)),
            (2.99, State(movesShown: 0, showsGame: true, showsDetails: true, isOver: false)),
            (3, State(movesShown: 1, showsGame: true, showsDetails: true, isOver: false)),
            (3.45, State(movesShown: 1, showsGame: true, showsDetails: true, isOver: false)),
            (3.5, State(movesShown: 2, showsGame: true, showsDetails: true, isOver: false)),
            (15.25, State(movesShown: 25, showsGame: true, showsDetails: true, isOver: false)),
            (27.49, State(movesShown: 49, showsGame: true, showsDetails: true, isOver: false)),
            (27.5, State(movesShown: 50, showsGame: true, showsDetails: true, isOver: false)),
            (37.49, State(movesShown: 50, showsGame: true, showsDetails: true, isOver: false)),
            (37.5, State(movesShown: 50, showsGame: false, showsDetails: true, isOver: false)),
            (39.5, State(movesShown: 50, showsGame: false, showsDetails: false, isOver: false)),
            (40.49, State(movesShown: 50, showsGame: false, showsDetails: false, isOver: false)),
            (40.5, State(movesShown: 50, showsGame: false, showsDetails: false, isOver: true)),
            (400, State(movesShown: 50, showsGame: false, showsDetails: false, isOver: true)),
        ]
        for (time, state) in expected {
            #expect(timeline.state(at: time) == state, "at \(time) s")
        }
    }

    @Test func aTwentyThreeMoveGame() {
        let timeline = SaverTimeline(moveCount: 23)
        #expect(timeline.time(ofMove: 23) == 14)
        #expect(timeline.fadeOutStart == 24)
        #expect(timeline.duration == 27)
        #expect(timeline.state(at: 13.99).movesShown == 22)
        #expect(timeline.state(at: 14).movesShown == 23)
        #expect(timeline.state(at: 23.99).showsGame)
        #expect(!timeline.state(at: 24).showsGame)
        #expect(timeline.state(at: 24).movesShown == 23)
        #expect(!timeline.state(at: 26.99).isOver)
        #expect(timeline.state(at: 27).isOver)
    }

    @Test func theFades() {
        let timeline = SaverTimeline(moveCount: 50)
        #expect(timeline.gameOpacity(at: -1) == 0)
        #expect(timeline.gameOpacity(at: 0) == 0)
        #expect(timeline.gameOpacity(at: 1) == 0.5)
        #expect(timeline.gameOpacity(at: 2) == 1)
        #expect(timeline.gameOpacity(at: 30) == 1)
        #expect(timeline.gameOpacity(at: 38.5) == 0.5)
        #expect(timeline.gameOpacity(at: 39.5) == 0)
        #expect(timeline.gameOpacity(at: 40) == 0)
        #expect(timeline.detailsOpacity(at: 0.5) == 0)
        #expect(timeline.detailsOpacity(at: 1.5) == 0.5)
        #expect(timeline.detailsOpacity(at: 2.25) == 1)
        #expect(timeline.detailsOpacity(at: 38.5) == 1, "the details fade out with the board")
        #expect(timeline.detailsOpacity(at: 39.5) == 0)
    }

    /// Ticks come ten times a second, but late and unevenly. Each lands on the move its time
    /// says, the moves never go back, and none is skipped while ticks come faster than moves.
    @Test(arguments: [1, 2, 3] as [UInt64])
    func irregularTicksLandOnTheRightMove(seed: UInt64) {
        let timeline = SaverTimeline(moveCount: 50)
        var generator = SeededGenerator(seed: seed)
        var time = 0.0
        var shown: [Int] = []
        while time < timeline.duration + 1 {
            time += Double.random(in: 0.02 ... 0.45, using: &generator)
            let state = timeline.state(at: time)
            let expected = time < 3 ? 0 : min(50, Int((time - 3) * 2) + 1)
            #expect(state.movesShown == expected, "at \(time) s")
            if shown.last != state.movesShown { shown.append(state.movesShown) }
        }
        #expect(shown == Array((shown.first ?? 0) ... 50))
    }

    /// The first game after the screensaver starts: in a second, and its first move a second
    /// later; the rest at the usual pace, with its last position held longer.
    @Test func theFirstGameComesInQuicker() {
        let usual = SaverTimeline(moveCount: 50)
        let timeline = SaverTimeline(moveCount: 50, opening: .start, extraHold: 2)
        #expect(timeline.gameOpacity(at: 0.5) == 0.5)
        #expect(timeline.gameOpacity(at: 1) == 1)
        #expect(!timeline.state(at: 0.29).showsDetails)
        #expect(timeline.state(at: 0.3).showsDetails)
        #expect(timeline.detailsOpacity(at: 1.3) == 1)
        #expect(timeline.detailsFadeInEnd == 1.3)
        #expect(timeline.state(at: 1.99).movesShown == 0)
        #expect(timeline.state(at: 2).movesShown == 1)
        #expect(timeline.time(ofMove: 50) == usual.time(ofMove: 50) - 1)
        #expect(timeline.fadeOutStart == usual.fadeOutStart - 1 + 2)
        #expect(timeline.duration == usual.duration - 1 + 2)
        #expect(SaverTimeline(moveCount: 50, extraHold: -1) == usual, "never a shorter hold")
    }

    @Test func aGameWithNoMovesStillEnds() {
        let timeline = SaverTimeline(moveCount: 0)
        #expect(timeline.state(at: 100).isOver)
        #expect(timeline.state(at: 5).movesShown == 0)
    }
}
