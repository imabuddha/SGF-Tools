import CoreGraphics
import CoreText
import Foundation
import SGFKit

/// The details shown beside a game's board, a line each, and each only if the game has it: the
/// players with their ranks, the result, the event, and the date, in the preview's words.
struct SaverDetails: Sendable, Equatable {
    /// What a line holds, which decides its size, its color, and its stone.
    enum Kind: Sendable, Equatable {
        case black
        case white
        case other
    }

    struct Line: Sendable, Equatable {
        let kind: Kind
        let text: String
    }

    let lines: [Line]

    /// The details of a game, with a hint after them (for the screensaver's own game).
    init(info: GameInfo, hint: String? = nil, locale: Locale = .current) {
        let summary = GameSummary(info: info, moveCount: 0, locale: locale)
        var lines: [Line] = []
        if let black = summary.black { lines.append(Line(kind: .black, text: black.name)) }
        if let white = summary.white { lines.append(Line(kind: .white, text: white.name)) }
        if let result = summary.result { lines.append(Line(kind: .other, text: result)) }
        if let event = info.event { lines.append(Line(kind: .other, text: event)) }
        if let date = info.date { lines.append(Line(kind: .other, text: GameSummary.describeDate(date, locale: locale))) }
        if let hint { lines.append(Line(kind: .other, text: hint)) }
        self.lines = lines
    }
}

/// Draws a game's details with Core Text into an image, for the screensaver and for the tests'
/// PNGs (see `docs/screensaver.md`, section 5).
///
/// Each player's line starts with a small drawn stone: a circle, since a text symbol would take
/// the text's color. The black one has a faint light rim, so that it shows on black. Every line's
/// text starts after the stones. The players are in the system font at 2.6% of the screen's
/// shorter side, in white at 95% opacity; the rest at 1.9%, at 70%. The block is at most 30% of
/// the screen's width (90% on a portrait screen), and a longer line ends in an ellipsis.
enum DetailsRenderer {
    /// One line, set.
    private struct SetLine {
        let kind: SaverDetails.Kind
        let line: CTLine
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
        let isTruncated: Bool
        /// The distance from the top of the block to this line's baseline.
        var baseline: CGFloat = 0
    }

    /// The lines of details set for a screen, and the block's size.
    private struct Typeset {
        var lines: [SetLine]
        let size: CGSize
        let textLeft: CGFloat
        let stoneDiameter: CGFloat
        let playerCapHeight: CGFloat
    }

    /// The size of the details' block on a screen, in points, or `nil` if there are no lines.
    static func size(of details: SaverDetails, on screen: CGSize) -> CGSize? {
        typeset(details, on: screen).map(\.size)
    }

    /// Each line's width as drawn, and whether it was cut short with an ellipsis.
    static func lineWidths(of details: SaverDetails, on screen: CGSize) -> [(width: CGFloat, isTruncated: Bool)] {
        typeset(details, on: screen)?.lines.map { ($0.width, $0.isTruncated) } ?? []
    }

    /// The details drawn for a screen, on a clear background, at a scale (2 for Retina), or `nil`
    /// if there are no lines.
    static func makeImage(of details: SaverDetails, on screen: CGSize, scale: CGFloat) -> CGImage? {
        guard let typeset = typeset(details, on: screen), scale > 0, scale.isFinite else { return nil }
        let width = Int((typeset.size.width * scale).rounded(.up))
        let height = Int((typeset.size.height * scale).rounded(.up))
        guard (1 ... 16384).contains(width), (1 ... 16384).contains(height),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        draw(typeset, in: context, scale: scale)
        return context.makeImage()
    }

    // MARK: - Setting

    private static func typeset(_ details: SaverDetails, on screen: CGSize) -> Typeset? {
        guard !details.lines.isEmpty, screen.width > 0, screen.height > 0 else { return nil }
        let shorter = min(screen.width, screen.height)
        let playerSize = shorter * Look.screensaverPlayerFontFraction
        let otherSize = shorter * Look.screensaverDetailFontFraction
        let playerFont = CTFontCreateUIFontForLanguage(.system, playerSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, playerSize, nil)
        let otherFont = CTFontCreateUIFontForLanguage(.system, otherSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, otherSize, nil)
        let stoneDiameter = playerSize * 0.72
        let textLeft = stoneDiameter + playerSize * 0.45
        let maximumTextWidth = max(1, SaverLayout.maximumDetailsWidth(for: screen) - textLeft)

        var lines: [SetLine] = []
        var top: CGFloat = 0
        var previous: SaverDetails.Kind?
        for detail in details.lines {
            let isPlayer = detail.kind != .other
            let font = isPlayer ? playerFont : otherFont
            let color = CGColor(gray: 1, alpha: isPlayer ? Look.screensaverPlayerOpacity : Look.screensaverDetailOpacity)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
            var line = CTLineCreateWithAttributedString(NSAttributedString(string: detail.text, attributes: attributes))
            var width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            var isTruncated = false
            if width > maximumTextWidth {
                let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
                if let truncated = CTLineCreateTruncatedLine(line, Double(maximumTextWidth), .end, ellipsis) {
                    line = truncated
                    width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                    isTruncated = true
                }
            }
            let ascent = CTFontGetAscent(font)
            let descent = CTFontGetDescent(font)
            // A little more space between the players and the rest.
            if previous != nil, previous != .other, !isPlayer { top += otherSize * 0.45 }
            var set = SetLine(kind: detail.kind, line: line, width: min(width, maximumTextWidth), ascent: ascent,
                              descent: descent, isTruncated: isTruncated)
            let lineHeight = (ascent + descent) * 1.2
            set.baseline = top + (lineHeight - ascent - descent) / 2 + ascent
            top += lineHeight
            lines.append(set)
            previous = detail.kind
        }
        let widest = lines.map(\.width).max() ?? 0
        let size = CGSize(width: min(SaverLayout.maximumDetailsWidth(for: screen), (textLeft + widest).rounded(.up)),
                          height: top.rounded(.up))
        return Typeset(lines: lines, size: size, textLeft: textLeft, stoneDiameter: stoneDiameter,
                       playerCapHeight: CTFontGetCapHeight(playerFont))
    }

    // MARK: - Drawing

    private static func draw(_ typeset: Typeset, in context: CGContext, scale: CGFloat) {
        let height = typeset.size.height
        context.textMatrix = .identity
        for line in typeset.lines {
            // Core Graphics has y pointing up; the lines were set from the top.
            let baseline = height - line.baseline
            if line.kind != .other {
                let center = CGPoint(x: typeset.stoneDiameter / 2, y: baseline + typeset.playerCapHeight / 2)
                drawStone(line.kind == .black ? .black : .white, at: center, diameter: typeset.stoneDiameter,
                          in: context, scale: scale)
            }
            context.textPosition = CGPoint(x: typeset.textLeft, y: baseline)
            CTLineDraw(line.line, context)
        }
    }

    private static func drawStone(_ color: StoneColor, at center: CGPoint, diameter: CGFloat, in context: CGContext,
                                  scale: CGFloat) {
        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        context.saveGState()
        switch color {
        case .black:
            let rim = max(1 / scale, diameter * 0.07)
            context.setFillColor(CGColor(gray: 0.08, alpha: 1))
            context.fillEllipse(in: rect)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.45))
            context.setLineWidth(rim)
            context.strokeEllipse(in: rect.insetBy(dx: rim / 2, dy: rim / 2))
        case .white:
            context.setFillColor(CGColor(gray: 0.93, alpha: 1))
            context.fillEllipse(in: rect)
        }
        context.restoreGState()
    }
}
