import SGFKit
import SGFRendering
import SwiftUI

/// What a file's preview shows: its first game's opening position and the game information.
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

/// A file's preview: the board on the left, and the game information beside it.
struct GamePreviewView: View {
    let preview: GamePreview

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 6) {
                BoardView(position: preview.position)
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GameInfoView(summary: preview.summary)
                .frame(width: Look.previewInfoWidth)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
    }

    /// Which position the board shows.
    private var caption: String {
        let position = preview.position
        if position.totalMoves == 0 {
            return "No moves"
        } else if position.isOpening {
            return "Move \(position.movesShown) of \(position.totalMoves)"
        } else {
            return "Final position, after \(position.totalMoves) move\(position.totalMoves == 1 ? "" : "s")"
        }
    }
}

/// The board, drawn by ``BoardRenderer`` at the view's size in pixels, with coordinates in the
/// secondary label color.
struct BoardView: View {
    let position: OpeningPosition

    @Environment(\.displayScale) private var displayScale
    @Environment(\.self) private var environment

    var body: some View {
        GeometryReader { geometry in
            if let image = image(size: geometry.size) {
                Image(decorative: image, scale: displayScale)
                    .accessibilityLabel("Board")
            }
        }
    }

    private func image(size: CGSize) -> CGImage? {
        let renderer = BoardRenderer(
            style: Look.previewStyle,
            showsCoordinates: true,
            coordinateSides: Look.previewCoordinateSides,
            coordinateColor: Color.secondary.resolve(in: environment).cgColor,
            margin: Look.previewMargin
        )
        let lastMove = Look.previewMarksLastMove ? position.lastMove : nil
        return renderer.makeImage(of: position.board, lastMove: lastMove, size: size, scale: displayScale)
    }
}

/// The game information: the players, the result, the other fields, and the game comment.
struct GameInfoView: View {
    let summary: GameSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = summary.title {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
            }
            if summary.black != nil || summary.white != nil || summary.result != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let black = summary.black { PlayerRow(color: .black, player: black) }
                    if let white = summary.white { PlayerRow(color: .white, player: white) }
                    if let result = summary.result {
                        Text(result)
                            .font(.headline)
                            .padding(.top, 2)
                    }
                }
                .textSelection(.enabled)
            }
            if !summary.fields.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                    ForEach(summary.fields, id: \.label) { field in
                        GridRow {
                            Text(field.label)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Text(field.value)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            if let comment = summary.gameComment {
                // A comment that fits is plain text; a longer one scrolls.
                ViewThatFits(in: .vertical) {
                    commentText(comment)
                    ScrollView {
                        commentText(comment)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentText(_ comment: String) -> some View {
        Text(comment)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

/// A player: a stone of their color, their name and rank, and their team.
private struct PlayerRow: View {
    let color: StoneColor
    let player: GameSummary.Player

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(color == .black ? Color.black : Color.white)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.45), lineWidth: 0.5))
                .frame(width: 12, height: 12)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                .accessibilityLabel(color == .black ? "Black" : "White")
            VStack(alignment: .leading, spacing: 1) {
                Text(player.name)
                    .font(.body.weight(.medium))
                if let team = player.team {
                    Text(team)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
