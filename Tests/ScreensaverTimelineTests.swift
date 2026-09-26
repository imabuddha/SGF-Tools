import Foundation
import Testing

@Suite("Screensaver: timeline")
struct ScreensaverTimelineTests {
    typealias State = SaverTimeline.State

    @Test func aFiftyMoveGame() {
        let timeline = SaverTimeline(moveCount: 50)
        #expect(timeline.duration == 60)
        #expect(timeline.fadeOutStart == 57)
        #expect(timeline.time(ofMove: 50) == 52)
        let expected: [(Double, State)] = [
            (-0.5, State(movesShown: 0, showsGame: false, showsDetails: false, isOver: false)),
            (0, State(movesShown: 0, showsGame: true, showsDetails: false, isOver: false)),
            (0.74, State(movesShown: 0, showsGame: true, showsDetails: false, isOver: false)),
            (0.75, State(movesShown: 0, showsGame: true, showsDetails: true, isOver: false)),
            (2.99, State(movesShown: 0, showsGame: true, showsDetails: true, isOver: false)),
            (3, State(movesShown: 1, showsGame: true, showsDetails: true, isOver: false)),
            (3.95, State(movesShown: 1, showsGame: true, showsDetails: true, isOver: false)),
            (4, State(movesShown: 2, showsGame: true, showsDetails: true, isOver: false)),
            (27.5, State(movesShown: 25, showsGame: true, showsDetails: true, isOver: false)),
            (51.99, State(movesShown: 49, showsGame: true, showsDetails: true, isOver: false)),
            (52, State(movesShown: 50, showsGame: true, showsDetails: true, isOver: false)),
            (56.99, State(movesShown: 50, showsGame: true, showsDetails: true, isOver: false)),
            (57, State(movesShown: 50, showsGame: false, showsDetails: true, isOver: false)),
            (59, State(movesShown: 50, showsGame: false, showsDetails: false, isOver: false)),
            (59.99, State(movesShown: 50, showsGame: false, showsDetails: false, isOver: false)),
            (60, State(movesShown: 50, showsGame: false, showsDetails: false, isOver: true)),
            (400, State(movesShown: 50, showsGame: false, showsDetails: false, isOver: true)),
        ]
        for (time, state) in expected {
            #expect(timeline.state(at: time) == state, "at \(time) s")
        }
    }

    @Test func aTwentyThreeMoveGame() {
        let timeline = SaverTimeline(moveCount: 23)
        #expect(timeline.time(ofMove: 23) == 25)
        #expect(timeline.fadeOutStart == 30)
        #expect(timeline.duration == 33)
        #expect(timeline.state(at: 24.99).movesShown == 22)
        #expect(timeline.state(at: 25).movesShown == 23)
        #expect(timeline.state(at: 29.99).showsGame)
        #expect(!timeline.state(at: 30).showsGame)
        #expect(timeline.state(at: 30).movesShown == 23)
        #expect(!timeline.state(at: 32.99).isOver)
        #expect(timeline.state(at: 33).isOver)
    }

    @Test func theFades() {
        let timeline = SaverTimeline(moveCount: 50)
        #expect(timeline.gameOpacity(at: -1) == 0)
        #expect(timeline.gameOpacity(at: 0) == 0)
        #expect(timeline.gameOpacity(at: 1) == 0.5)
        #expect(timeline.gameOpacity(at: 2) == 1)
        #expect(timeline.gameOpacity(at: 30) == 1)
        #expect(timeline.gameOpacity(at: 58) == 0.5)
        #expect(timeline.gameOpacity(at: 59) == 0)
        #expect(timeline.gameOpacity(at: 59.5) == 0)
        #expect(timeline.detailsOpacity(at: 0.5) == 0)
        #expect(timeline.detailsOpacity(at: 1.5) == 0.5)
        #expect(timeline.detailsOpacity(at: 2.25) == 1)
        #expect(timeline.detailsOpacity(at: 58) == 1, "the details fade out with the board")
        #expect(timeline.detailsOpacity(at: 59) == 0)
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
            time += Double.random(in: 0.02 ... 0.6, using: &generator)
            let state = timeline.state(at: time)
            let expected = time < 3 ? 0 : min(50, Int(time - 3) + 1)
            #expect(state.movesShown == expected, "at \(time) s")
            if shown.last != state.movesShown { shown.append(state.movesShown) }
        }
        #expect(shown == Array((shown.first ?? 0) ... 50))
    }

    /// The first game after the screensaver starts: in a second, and its first move a second
    /// later; the rest as usual, with its last position held longer.
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
