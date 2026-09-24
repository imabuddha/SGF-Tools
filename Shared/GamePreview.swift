import Foundation
import SGFKit

/// What a file's preview shows: its first game's opening position and the game information
/// (see ``GamePreviewView``).
struct GamePreview: Sendable {
    let position: OpeningPosition
    let summary: GameSummary

    /// The preview of an SGF file, or `nil` if it has no game tree. The whole file is read, so
    /// that the number of games is known.
    ///
    /// - Throws: Only if the file can't be read.
    init?(contentsOf url: URL) throws {
        try self.init(collection: SGFCollection(contentsOf: url))
    }

    /// The preview of a parsed file, or `nil` if it has no games.
    init?(collection: SGFCollection, locale: Locale = .current) {
        guard let game = collection.games.first,
              let summary = GameSummary(collection: collection, locale: locale)
        else { return nil }
        position = OpeningPosition(game: game)
        self.summary = summary
    }
}
