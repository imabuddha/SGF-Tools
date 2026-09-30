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
    /// The board's canvas, once the first board is drawn, which draws the moves after it. The
    /// player takes it when the game begins.
    var canvas: BoardCanvas?
    /// The board before the first move, once drawn. The screensaver draws the next game's only
    /// when the current game has reached its last move, so that a screen holds two boards at a
    /// time.
    var firstBoard: CGImage?
    /// How long the first board took to draw, in milliseconds.
    var firstBoardTime: Double?
}

extension PreparedGame {
    /// Makes the board's canvas and draws the board before the first move, off the main thread.
    mutating func drawFirstBoard() {
        let start = ContinuousClock.now
        canvas = BoardCanvas(game: game, side: layout.board.width, scale: scale)
        canvas?.draw(afterMoves: 0)
        firstBoard = canvas?.image()
        firstBoardTime = (ContinuousClock.now - start) / .milliseconds(1)
    }

    /// The board's size in pixels, as its canvas makes it.
    var boardPixels: Int { Int((layout.board.width * scale).rounded()) }
}

/// One screen's layers, and applying a moment of the timeline to them (see
/// `docs/screensaver.md`, section 3).
///
/// A black root layer holds the **game layer**, whose opacity makes the fades, and in it the
/// **board** and the **details**. The board layer shows the board as a whole image. A move
/// fades in only the **tiles** it changes (see ``BoardCanvas``): each is a small layer over the
/// board, made the first time its tile changes and faded to its new image after that, so the new
/// stone appears and captured stones vanish together, and the rest of the board, unchanged, is
/// left alone. Once the last move has faded in, the player puts the whole last position back in
/// the board layer and the tiles go, so the game layer's fade-out has one flat layer under it.
/// The game layer has no group opacity: its board and details don't overlap, so fading each on
/// its own looks the same, without an offscreen pass.
///
/// The fades are Core Animation animations, so nothing runs between moves, and each moment is
/// one transaction, or none when nothing changes. Frames are on whole pixels, so the images are
/// shown pixel for pixel. The same layers render the tests' images, with the timeline's
/// opacities set directly instead of animated.
@MainActor
final class SaverScene {
    /// The black layer everything is in: the view's own layer, or a test's.
    let rootLayer: CALayer
    private let gameLayer = CALayer()
    private let boardLayer = CALayer()
    private let detailsLayer = CALayer()
    /// The tiles over the board, by their place in the canvas's grid.
    private var tileLayers: [Int: CALayer] = [:]
    private var applied: SaverTimeline.State?

    /// What the scene has asked of Core Animation, for the tests that measure the load.
    struct Stats: Sendable, Equatable {
        /// The transactions committed.
        var commits = 0
        /// The pixels of the images set as layers' contents, each one uploaded to the GPU.
        var uploadedPixels = 0
        /// The fades of moves, and the pixels they animate, each for ``Look/screensaverMoveFade``.
        var moveFades = 0
        var moveFadePixels = 0
        /// The fades of the game and details layers.
        var gameFades = 0
    }

    private(set) var stats = Stats()

    /// The game shown, if any.
    private(set) var prepared: PreparedGame?

    /// The number of tiles over the board.
    var tileCount: Int { tileLayers.count }

    /// Whether the game layer fades as a group, which it does only if its fade-out starts while
    /// tiles are still over the board.
    var fadesAsGroup: Bool { gameLayer.allowsGroupOpacity }

    /// The board's frame in the root layer.
    var boardFrame: CGRect { boardLayer.frame }

    init(rootLayer: CALayer) {
        self.rootLayer = rootLayer
        rootLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        for layer in [gameLayer, boardLayer, detailsLayer] {
            layer.opacity = 0
            layer.contentsGravity = .resize
            layer.actions = Self.noActions
        }
        gameLayer.allowsGroupOpacity = false
        gameLayer.addSublayer(boardLayer)
        gameLayer.addSublayer(detailsLayer)
        rootLayer.addSublayer(gameLayer)
    }

    private static let noActions: [String: any CAAction] = [
        "contents": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "position": NSNull(),
        "sublayers": NSNull(), "onOrderIn": NSNull(), "onOrderOut": NSNull(),
    ]

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
    /// nothing), drawn in full as a canvas draws it: as the preview draws it, without
    /// coordinates, on black.
    nonisolated static func boardImage(of game: SaverGame, afterMoves moves: Int, side: CGFloat, scale: CGFloat) -> CGImage? {
        guard let canvas = BoardCanvas(game: game, side: side, scale: scale) else { return nil }
        canvas.draw(afterMoves: moves)
        return canvas.image()
    }

    /// A rect moved to whole pixels, with the size of its image in pixels if it has one, so the
    /// image is shown pixel for pixel.
    nonisolated static func aligned(_ rect: CGRect, pixels: (width: Int, height: Int)?, scale: CGFloat) -> CGRect {
        let origin = CGPoint(x: (rect.minX * scale).rounded() / scale, y: (rect.minY * scale).rounded() / scale)
        guard let pixels else { return CGRect(origin: origin, size: rect.size) }
        return CGRect(origin: origin, size: CGSize(width: CGFloat(pixels.width) / scale, height: CGFloat(pixels.height) / scale))
    }

    // MARK: - Showing

    /// Puts a game on the layers, invisible, with the board before its first move.
    func show(_ prepared: PreparedGame) {
        self.prepared = prepared
        applied = nil
        transaction {
            for layer in [gameLayer, boardLayer, detailsLayer] {
                layer.removeAllAnimations()
                layer.contentsScale = prepared.scale
            }
            removeTiles()
            gameLayer.frame = rootLayer.bounds
            gameLayer.opacity = 0
            gameLayer.allowsGroupOpacity = false
            boardLayer.frame = Self.aligned(prepared.layout.board, pixels: (prepared.boardPixels, prepared.boardPixels),
                                            scale: prepared.scale)
            boardLayer.contents = prepared.firstBoard
            boardLayer.opacity = 1
            detailsLayer.frame = Self.aligned(prepared.layout.details ?? .zero,
                                              pixels: prepared.details.map { ($0.width, $0.height) }, scale: prepared.scale)
            detailsLayer.contents = prepared.details
            detailsLayer.opacity = 0
            stats.uploadedPixels += Self.pixels(of: prepared.firstBoard) + Self.pixels(of: prepared.details)
        }
    }

    /// Shows a moment of the game: the fades that start or end there, and the move's tiles, if
    /// any, in one transaction, or none if nothing changes. Animated, each fade runs from the
    /// timeline's value at `time` to its end, over the time left, so a late tick doesn't make
    /// it longer. Not animated, the layers get the timeline's values at `time`.
    func apply(_ state: SaverTimeline.State, at time: Double, animated: Bool, board update: BoardUpdate? = nil) {
        guard let timeline = prepared?.timeline else { return }
        let fades = state.showsGame != applied?.showsGame || state.showsDetails != applied?.showsDetails
        defer { applied = state }
        guard !animated || fades || update != nil else { return }
        transaction {
            if animated {
                if state.showsGame != applied?.showsGame {
                    // Tiles are still over the board only if the last position never came back
                    // whole; fading them each on its own would show the board through them.
                    if !state.showsGame, !tileLayers.isEmpty { gameLayer.allowsGroupOpacity = true }
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
            if let update { place(update, animated: animated) }
        }
    }

    /// Shows a move's tiles, fading them in when animated.
    func showBoard(_ update: BoardUpdate, animated: Bool) {
        transaction { place(update, animated: animated) }
    }

    /// Shows a whole board, with no tiles over it: the first board when it comes late, and the
    /// last position once its move has faded in, which looks the same as the tiles did.
    func setBoard(_ image: CGImage?) {
        transaction {
            removeTiles()
            boardLayer.contents = image
            stats.uploadedPixels += Self.pixels(of: image)
        }
    }

    /// Lets go of the game and its images, leaving the screen black.
    func clear() {
        transaction {
            for layer in [gameLayer, boardLayer, detailsLayer] { layer.removeAllAnimations() }
            removeTiles()
            gameLayer.opacity = 0
            boardLayer.contents = nil
            detailsLayer.contents = nil
        }
        prepared = nil
        applied = nil
    }

    // MARK: - Tiles

    /// Puts a move's tiles over the board. A tile seen for the first time is a new layer that
    /// fades in over the board, which still shows the tile as it was; a tile seen before fades
    /// from its old image to the new one. Either way each pixel goes from old to new as a whole
    /// board's fade took it.
    private func place(_ update: BoardUpdate, animated: Bool) {
        guard let scale = prepared?.scale else { return }
        let height = boardLayer.bounds.height
        for tile in update.tiles {
            if let layer = tileLayers[tile.index] {
                if animated {
                    let transition = CATransition()
                    transition.type = .fade
                    transition.duration = Look.screensaverMoveFade
                    layer.add(transition, forKey: "move")
                }
                layer.contents = tile.image
            } else {
                let layer = CALayer()
                layer.actions = Self.noActions
                layer.contentsGravity = .resize
                layer.contentsScale = scale
                layer.frame = CGRect(x: CGFloat(tile.rect.x) / scale,
                                     y: height - CGFloat(tile.rect.y + tile.rect.height) / scale,
                                     width: CGFloat(tile.rect.width) / scale, height: CGFloat(tile.rect.height) / scale)
                layer.contents = tile.image
                if animated {
                    let fadeIn = CABasicAnimation(keyPath: "opacity")
                    fadeIn.fromValue = 0
                    fadeIn.toValue = 1
                    fadeIn.duration = Look.screensaverMoveFade
                    layer.add(fadeIn, forKey: "move")
                }
                boardLayer.addSublayer(layer)
                tileLayers[tile.index] = layer
            }
            stats.uploadedPixels += tile.rect.area
            if animated { stats.moveFadePixels += tile.rect.area }
        }
        if animated { stats.moveFades += 1 }
    }

    private func removeTiles() {
        for layer in tileLayers.values { layer.removeFromSuperlayer() }
        tileLayers = [:]
    }

    // MARK: - Transactions and fades

    private func transaction(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
        stats.commits += 1
    }

    private static func pixels(of image: CGImage?) -> Int {
        image.map { $0.width * $0.height } ?? 0
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
        stats.gameFades += 1
    }
}
