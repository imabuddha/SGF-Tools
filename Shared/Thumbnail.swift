import CoreGraphics
import Foundation
import SGFKit
import SGFRendering

/// A file's thumbnail: its first game's opening position (see ``OpeningPosition``), on a stack
/// of boards if the file holds more than one game.
struct Thumbnail: Sendable {
    /// The position shown.
    let position: OpeningPosition

    /// Whether the file holds more than one game.
    let isCollection: Bool

    /// The thumbnail of an SGF file, or `nil` if the file has no game tree. Only the first game
    /// is read.
    ///
    /// - Throws: Only if the file can't be read.
    init?(contentsOf url: URL) throws {
        let collection = try SGFCollection(contentsOf: url, options: .init(stopAfterFirstGame: true))
        self.init(collection: collection)
    }

    /// The thumbnail of a parsed file, or `nil` if it has no games.
    init?(collection: SGFCollection) {
        guard let game = collection.games.first else { return nil }
        position = OpeningPosition(game: game)
        isCollection = collection.isCollection
    }

    /// The renderer for thumbnails.
    static let renderer = BoardRenderer(style: Look.thumbnailStyle, margin: Look.thumbnailMargin)

    /// Draws the thumbnail, fitted and centered in a rect.
    func draw(in context: CGContext, rect: CGRect) {
        let lastMove = Look.thumbnailMarksLastMove ? position.lastMove : nil
        if isCollection, Look.thumbnailShowsCollectionBackdrop {
            Self.renderer.drawCollection(position.board, lastMove: lastMove, in: context, rect: rect)
        } else {
            Self.renderer.draw(position.board, lastMove: lastMove, in: context, rect: rect)
        }
    }

    /// Makes an image of the thumbnail, `size` times `scale` pixels, transparent where the board
    /// doesn't fill it.
    func makeImage(size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        draw(in: context, rect: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    /// The size to draw a thumbnail at: the largest square that fits the size Quick Look allows.
    static func contextSize(fitting maximumSize: CGSize) -> CGSize {
        let side = max(1, min(maximumSize.width, maximumSize.height).rounded(.down))
        return CGSize(width: side, height: side)
    }
}
