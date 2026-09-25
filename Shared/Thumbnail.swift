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

    /// The size to draw a thumbnail at: the largest square that fits the size Quick Look allows,
    /// up to ``maximumSide``.
    static func contextSize(fitting maximumSize: CGSize) -> CGSize {
        let side = max(1, min(maximumSize.width, maximumSize.height, maximumSide).rounded(.down))
        return CGSize(width: side, height: side)
    }

    /// The largest side of a thumbnail, in points: far beyond any size Finder shows, so that an
    /// infinite or absurd size from Quick Look can't become the size of the context.
    private static let maximumSide: CGFloat = 16384
}
