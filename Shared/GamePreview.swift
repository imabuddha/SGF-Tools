import Foundation
import SGFKit

/// What a file's preview shows: its first game's opening position and the game information
/// (see ``GamePreviewView``).
struct GamePreview: Sendable {
    let position: OpeningPosition
    let summary: GameSummary

    /// The largest file that is read in full, so that the preview can count its games: 2 MB, as
    /// for Spotlight. Of a larger file, only the first game is read, as for thumbnails, and the
    /// preview says that the file holds several games.
    ///
    /// Parsing takes about 30 times a file's size in memory (see `docs/spotlight-notes.md`): read
    /// in full, a collection of 20 MB would take a second and half a gigabyte. The largest SGF
    /// file found so far, 1.78 MB, is read in full.
    static let wholeFileLimit = 2 << 20

    /// The preview of an SGF file, or `nil` if it has no game tree. A file of up to
    /// `wholeFileLimit` bytes is read in full, so that the number of games is known; of a larger
    /// one, only the first game is read.
    ///
    /// - Throws: Only if the file can't be read.
    init?(contentsOf url: URL, wholeFileLimit: Int = GamePreview.wholeFileLimit) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let options = SGFParser.Options(stopAfterFirstGame: size > wholeFileLimit)
        try self.init(collection: SGFCollection(contentsOf: url, options: options))
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
