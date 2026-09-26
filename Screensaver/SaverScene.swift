import CoreGraphics
import Foundation
import QuartzCore
import SGFKit
import SGFRendering

/// A game made ready for one screen off the main thread: where everything goes, the details'
/// image, and the board before the first move.
struct PreparedGame: Sendable {
    let game: SaverGame
    let layout: SaverLayout
    /// The game's timeline; the player gives the first game after it starts a quicker one.
    var timeline: SaverTimeline
    /// The screen's backing scale, which the images are drawn at.
    let scale: CGFloat
    let details: CGImage?
    /// The board before the first move, once drawn. The screensaver draws the next game's only
    /// when the current game has reached its last move, so that a screen holds two boards at a
    /// time.
    var firstBoard: CGImage?
    /// How long the first board took to draw, in milliseconds.
    var firstBoardTime: Double?
}

extension PreparedGame {
    /// Draws the board before the first move, off the main thread.
    mutating func drawFirstBoard() {
        let start = ContinuousClock.now
        firstBoard = SaverScene.boardImage(of: game, afterMoves: 0, side: layout.board.width, scale: scale)
        firstBoardTime = (ContinuousClock.now - start) / .milliseconds(1)
    }
}

/// One screen's layers, and applying a moment of the timeline to them (see
/// `docs/screensaver.md`, section 3).
///
/// A black root layer holds the **game layer**, whose opacity makes the fades, and in it the
/// **board** and the **details**. A move replaces the board's image inside a short fade, so the
/// new stone appears and captured stones vanish together. The fades are Core Animation
/// animations, so nothing runs between moves. The same layers render the tests' images, with
/// the timeline's opacities set directly instead of animated.
@MainActor
final class SaverScene {
    /// The black layer everything is in: the view's own layer, or a test's.
    let rootLayer: CALayer
    private let gameLayer = CALayer()
    private let boardLayer = CALayer()
    private let detailsLayer = CALayer()
    private var applied: SaverTimeline.State?

    /// The game shown, if any.
    private(set) var prepared: PreparedGame?

    init(rootLayer: CALayer) {
        self.rootLayer = rootLayer
        rootLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        for layer in [gameLayer, boardLayer, detailsLayer] {
            layer.opacity = 0
            layer.contentsGravity = .resize
            layer.actions = ["contents": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "position": NSNull()]
        }
        gameLayer.addSublayer(boardLayer)
        gameLayer.addSublayer(detailsLayer)
        rootLayer.addSublayer(gameLayer)
    }

    // MARK: - Preparing, off the main thread

    /// Lays a game out for a screen and draws its details, and its first board if asked, or
    /// returns `nil` if the screen has no area.
    nonisolated static func prepare(_ game: SaverGame, screen: CGSize, scale: CGFloat, drawingFirstBoard: Bool = true,
                                    using generator: inout some RandomNumberGenerator) -> PreparedGame? {
        let detailsSize = SaverLayout.isPreview(screen) ? nil : DetailsRenderer.size(of: game.details, on: screen)
        guard let layout = SaverLayout(screen: screen, details: detailsSize, using: &generator) else { return nil }
        let details = layout.details == nil ? nil : DetailsRenderer.makeImage(of: game.details, on: screen, scale: scale)
        var prepared = PreparedGame(game: game, layout: layout, timeline: SaverTimeline(moveCount: game.moveCount),
                                    scale: scale, details: details)
        if drawingFirstBoard { prepared.drawFirstBoard() }
        return prepared
    }

    /// The board after a number of moves, the last one marked with a ring (a pass marks
    /// nothing), drawn as the preview draws it, without coordinates.
    nonisolated static func boardImage(of game: SaverGame, afterMoves moves: Int, side: CGFloat, scale: CGFloat) -> CGImage? {
        let moves = min(max(0, moves), game.moveCount)
        let renderer = BoardRenderer(style: Look.screensaverStyle, margin: Look.screensaverMargin)
        return renderer.makeImage(of: game.positions[moves],
                                  lastMove: Look.screensaverMarksLastMove ? game.lastMoves[moves] : nil,
                                  size: CGSize(width: side, height: side), scale: scale)
    }

    // MARK: - Showing

    /// Puts a game on the layers, invisible, with the board before its first move.
    func show(_ prepared: PreparedGame) {
        self.prepared = prepared
        applied = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [gameLayer, boardLayer, detailsLayer] {
            layer.removeAllAnimations()
            layer.contentsScale = prepared.scale
        }
        gameLayer.frame = rootLayer.bounds
        gameLayer.opacity = 0
        boardLayer.frame = prepared.layout.board
        boardLayer.contents = prepared.firstBoard
        boardLayer.opacity = 1
        detailsLayer.frame = prepared.layout.details ?? .zero
        detailsLayer.contents = prepared.details
        detailsLayer.opacity = 0
        CATransaction.commit()
    }

    /// Shows a moment of the game: the fades that start or end there. Animated, each fade runs
    /// from the timeline's value at `time` to its end, over the time left, so a late tick
    /// doesn't make it longer. Not animated, the layers get the timeline's values at `time`.
    func apply(_ state: SaverTimeline.State, at time: Double, animated: Bool) {
        guard let timeline = prepared?.timeline else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            if state.showsGame != applied?.showsGame {
                let end = state.showsGame ? timeline.opening.fadeIn : timeline.fadeOutEnd
                fade(gameLayer, to: state.showsGame ? 1 : 0, from: timeline.gameOpacity(at: time), over: end - time)
            }
            if state.showsDetails != applied?.showsDetails {
                let end = state.showsDetails ? timeline.detailsFadeInEnd : time
                fade(detailsLayer, to: state.showsDetails ? 1 : 0, from: timeline.detailsOpacity(at: time), over: end - time)
            }
        } else {
            gameLayer.removeAllAnimations()
            detailsLayer.removeAllAnimations()
            gameLayer.opacity = Float(timeline.gameOpacity(at: time))
            detailsLayer.opacity = Float(timeline.detailsOpacity(at: time))
        }
        CATransaction.commit()
        applied = state
    }

    /// Replaces the board's image, inside a short fade when animated.
    func setBoard(_ image: CGImage?, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = Look.screensaverMoveFade
            boardLayer.add(transition, forKey: "move")
        }
        boardLayer.contents = image
        CATransaction.commit()
    }

    /// Lets go of the game and its images, leaving the screen black.
    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [gameLayer, boardLayer, detailsLayer] { layer.removeAllAnimations() }
        gameLayer.opacity = 0
        boardLayer.contents = nil
        detailsLayer.contents = nil
        CATransaction.commit()
        prepared = nil
        applied = nil
    }

    /// Sets a layer's opacity, fading to it from `from` over `duration` seconds if that is more
    /// than none.
    private func fade(_ layer: CALayer, to target: Double, from start: Double, over duration: Double) {
        layer.removeAnimation(forKey: "fade")
        layer.opacity = Float(target)
        guard duration > 0.01, start != target else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = start
        animation.toValue = target
        animation.duration = duration
        layer.add(animation, forKey: "fade")
    }
}
