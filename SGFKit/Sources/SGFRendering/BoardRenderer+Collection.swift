import CoreGraphics
import SGFKit

extension BoardRenderer {
    /// The number of boards stacked behind the front board of a collection, as in 1.x.
    public static let collectionDepth = 3

    /// Draws the backdrop that marks a file holding several games: a few boards stacked behind
    /// and below to the right, fading as they go back, as SGF Tools 1.x did.
    ///
    /// The stack and the front board together are fitted and centered in `rect`. Draw the front
    /// board into the returned rect, or use ``drawCollection(_:lastMove:in:rect:)``, which does
    /// both.
    ///
    /// - Returns: The rect for the front board in user space, or `CGRect.null` if `rect` is
    ///   empty.
    @discardableResult
    public func drawCollectionBackdrop(for size: BoardSize, in context: CGContext, rect: CGRect) -> CGRect {
        Self.inPixelSpace(of: context, rect: rect) { pixelRect in
            let step = max(1, (min(pixelRect.width, pixelRect.height) * 0.028).rounded())
            let span = step * CGFloat(Self.collectionDepth)
            guard pixelRect.width > span, pixelRect.height > span else { return nil }
            let available = CGRect(x: pixelRect.minX, y: pixelRect.minY + span,
                                   width: pixelRect.width - span, height: pixelRect.height - span)
            guard let layout = BoardLayout(size: size, in: available, margin: margin, wantsLabels: showsCoordinates)
            else { return nil }

            let board = layout.boardRect.size
            let left = (pixelRect.midX - (board.width + span) / 2).rounded()
            let top = (pixelRect.midY + (board.height + span) / 2).rounded()
            let front = CGRect(x: left, y: top - board.height, width: board.width, height: board.height)

            let palette = Palette.of(style.look)
            for depth in stride(from: Self.collectionDepth, through: 1, by: -1) {
                let offset = step * CGFloat(depth)
                let back = front.offsetBy(dx: offset, dy: -offset)
                let alpha = 1 - 0.22 * CGFloat(depth)
                context.setFillColor(palette.board.copy(alpha: alpha) ?? palette.board)
                context.fill(back)
                let edge = palette.boardEdge
                Self.fillEdge(of: back, color: edge.copy(alpha: edge.alpha * alpha) ?? edge, in: context)
            }
            return front
        }
    }

    /// Draws a position on top of the collection backdrop.
    ///
    /// - Returns: The front board's rect in user space, or `CGRect.null` if `rect` is empty.
    @discardableResult
    public func drawCollection(
        _ board: Board, lastMove: SGFPoint? = nil, in context: CGContext, rect: CGRect
    ) -> CGRect {
        let front = drawCollectionBackdrop(for: board.size, in: context, rect: rect)
        guard !front.isNull else { return .null }
        return draw(board, lastMove: lastMove, in: context, rect: front)
    }

    /// Makes an image of a position on top of the collection backdrop; see
    /// ``makeImage(of:lastMove:size:scale:)``.
    public func makeCollectionImage(
        of board: Board, lastMove: SGFPoint? = nil, size: CGSize, scale: CGFloat = 1
    ) -> CGImage? {
        Self.makeImage(size: size, scale: scale) { context, rect in
            drawCollection(board, lastMove: lastMove, in: context, rect: rect)
        }
    }
}
