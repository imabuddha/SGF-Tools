import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SGFKit
import SGFRendering
import Testing
import UniformTypeIdentifiers

/// Renders sample images and a contact sheet for judging the look, when the environment
/// variable `SGF_RENDER_SAMPLES` names a directory to write them to:
///
///     SGF_RENDER_SAMPLES=/tmp/samples swift test --filter Samples
///
/// Skipped otherwise.
@Suite("Samples")
struct SampleSheet {
    static let directory = ProcessInfo.processInfo.environment["SGF_RENDER_SAMPLES"]

    private struct Subject {
        let name: String
        let title: String
        let board: Board
        var lastMove: SGFPoint?
        var isCollection = false
    }

    private static let sizes: [CGFloat] = [64, 128, 256, 512]

    @Test(.enabled(if: directory != nil))
    func renderSamples() throws {
        let directory = URL(fileURLWithPath: try #require(Self.directory), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let john = try Fixtures.johnVsGnu()
        let endMoves = john.mainLineMoveCount
        let subjects = [
            Subject(name: "johnVsGnu-50", title: "johnVsGnu.sgf after 50 moves",
                    board: john.position(afterMainLineMoves: 50)),
            Subject(name: "johnVsGnu-end", title: "johnVsGnu.sgf at the end (\(endMoves) moves)",
                    board: john.position(afterMainLineMoves: endMoves)),
            Subject(name: "13x13", title: "13x13 position (made up)",
                    board: game(Fixtures.thirteenByThirteen).position(afterMainLineMoves: .max)),
            Subject(name: "9x9", title: "9x9 position (made up)",
                    board: game(Fixtures.nineByNine).position(afterMainLineMoves: .max)),
            Subject(name: "19x13", title: "19x13 rectangular board (made up)",
                    board: game(Fixtures.nineteenByThirteen).position(afterMainLineMoves: .max)),
            Subject(name: "collection", title: "Collection backdrop (3 made-up games)",
                    board: game(Fixtures.collection).position(afterMainLineMoves: .max), isCollection: true),
        ]

        // The requested samples, one PNG each.
        var rendered: [[BoardStyle: [CGImage]]] = []
        for subject in subjects {
            var byStyle: [BoardStyle: [CGImage]] = [:]
            for style in BoardStyle.builtIn {
                let renderer = BoardRenderer(style: style)
                byStyle[style] = try Self.sizes.map { side in
                    let size = CGSize(width: side, height: side)
                    let image = try #require(subject.isCollection
                        ? renderer.makeCollectionImage(of: subject.board, size: size)
                        : renderer.makeImage(of: subject.board, size: size))
                    try Self.writePNG(image, to: directory.appendingPathComponent(
                        "\(subject.name)-\(style.identifier)-\(Int(side)).png"))
                    return image
                }
            }
            rendered.append(byStyle)
        }

        // Extras: the options, and the smallest sizes.
        // The game ends with two passes; mark the last stone played.
        let stonesPlayed = john.mainLine.compactMap { $0.move(on: john.boardSize)?.point }
        let lastMove = try #require(stonesPlayed.last)
        let endBoard = john.position(afterMainLineMoves: endMoves)
        var optionImages: [(String, CGImage)] = []
        for style in BoardStyle.builtIn {
            let renderer = BoardRenderer(style: style, showsCoordinates: true, margin: 0.5)
            for side in [256.0, 512.0] {
                let image = try #require(renderer.makeImage(
                    of: endBoard, lastMove: lastMove, size: CGSize(width: side, height: side)))
                try Self.writePNG(image, to: directory.appendingPathComponent(
                    "options-\(style.identifier)-\(Int(side)).png"))
                optionImages.append(("\(style.identifier) \(Int(side))", image))
            }
        }
        var smallImages: [(String, [CGImage])] = []
        for style in BoardStyle.builtIn {
            let renderer = BoardRenderer(style: style)
            for subject in [subjects[0], subjects[2], subjects[3]] {
                var pair: [CGImage] = []
                for side in [16.0, 32.0] {
                    let image = try #require(renderer.makeImage(of: subject.board, size: CGSize(width: side, height: side)))
                    try Self.writePNG(image, to: directory.appendingPathComponent(
                        "small-\(subject.name)-\(style.identifier)-\(Int(side)).png"))
                    pair.append(image)
                }
                smallImages.append(("\(subject.name), \(style.identifier)", pair))
            }
        }

        let sheet = try #require(Self.contactSheet(
            subjects: subjects.map(\.title), rendered: rendered,
            options: optionImages, small: smallImages
        ))
        try Self.writePNG(sheet, to: directory.appendingPathComponent("contact-sheet.png"))
    }

    // MARK: - Contact sheet

    private static let gap: CGFloat = 16
    private static let groupGap: CGFloat = 56
    private static let edge: CGFloat = 28
    private static let titleHeight: CGFloat = 30
    private static let captionHeight: CGFloat = 22

    private static func contactSheet(
        subjects: [String], rendered: [[BoardStyle: [CGImage]]],
        options: [(String, CGImage)], small: [(String, [CGImage])]
    ) -> CGImage? {
        let groupWidth = sizes.reduce(0, +) + gap * CGFloat(sizes.count - 1)
        let width = edge * 2 + groupWidth * 2 + groupGap
        let rowHeight = titleHeight + 512 + captionHeight + gap
        let magnify: CGFloat = 4
        let smallRowHeight = titleHeight + 32 * magnify + captionHeight + gap
        let height = edge * 2 + titleHeight + rowHeight * CGFloat(subjects.count + 1) + smallRowHeight + gap * 2

        guard let context = CGContext(
            data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Work top-down: flip, and flip each image back when drawing it.
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        var y = edge
        text("SGFRendering samples: shaded on the left, flat on the right, at 64, 128, 256, and 512 px",
             at: CGPoint(x: edge, y: y + 20), size: 17, bold: true, in: context)
        y += titleHeight

        for (title, byStyle) in zip(subjects, rendered) {
            text(title, at: CGPoint(x: edge, y: y + 20), size: 15, bold: true, in: context)
            var x = edge
            for style in BoardStyle.builtIn {
                for (side, image) in zip(sizes, byStyle[style] ?? []) {
                    let top = y + titleHeight + 512 - side
                    draw(image, in: CGRect(x: x, y: top, width: side, height: side), context: context)
                    text("\(style.identifier) \(Int(side))", at: CGPoint(x: x, y: y + titleHeight + 512 + 16),
                         size: 11, bold: false, in: context)
                    x += side + gap
                }
                x += groupGap - gap
            }
            y += rowHeight
        }

        text("Extras: coordinates, a 0.5-cell margin, and the last-move marker (end of johnVsGnu.sgf)",
             at: CGPoint(x: edge, y: y + 20), size: 15, bold: true, in: context)
        var x = edge
        for (label, image) in options {
            let side = CGFloat(image.width)
            let top = y + titleHeight + 512 - side
            draw(image, in: CGRect(x: x, y: top, width: side, height: side), context: context)
            text(label, at: CGPoint(x: x, y: y + titleHeight + 512 + 16), size: 11, bold: false, in: context)
            x += side + gap
        }
        y += rowHeight

        text("Extras: 16 and 32 px, each at actual size and magnified 4x (johnVsGnu at 50 moves, 13x13, 9x9)",
             at: CGPoint(x: edge, y: y + 20), size: 15, bold: true, in: context)
        x = edge
        for (label, pair) in small {
            let top = y + titleHeight
            text(label, at: CGPoint(x: x, y: top + 32 * magnify + 16), size: 11, bold: false, in: context)
            for image in pair {
                let side = CGFloat(image.width)
                draw(image, in: CGRect(x: x, y: top, width: side, height: side), context: context)
                context.interpolationQuality = .none
                draw(image, in: CGRect(x: x + side + 4, y: top, width: side * magnify, height: side * magnify),
                     context: context)
                context.interpolationQuality = .default
                x += side * (magnify + 1) + 4 + 8
            }
            x += gap
        }
        return context.makeImage()
    }

    /// Draws an image right side up in the flipped sheet.
    private static func draw(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// Draws a line of text with its baseline at a point of the flipped sheet.
    private static func text(_ string: String, at point: CGPoint, size: CGFloat, bold: Bool, in context: CGContext) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
