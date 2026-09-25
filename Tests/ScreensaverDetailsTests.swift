import CoreGraphics
import Foundation
import SGFKit
import Testing

@Suite("Screensaver: details")
struct ScreensaverDetailsTests {
    static let locale = Locale(identifier: "en_US")
    static let screen = CGSize(width: 1920, height: 1080)

    static func details(_ sgf: String, hint: String? = nil) throws -> SaverDetails {
        SaverDetails(info: GameInfo(game: try game(sgf)), hint: hint, locale: locale)
    }

    @Test func theWordingAndOrder() throws {
        let details = try Self.details(namedGame())
        #expect(details.lines == [
            .init(kind: .black, text: "Black Tester 3d"),
            .init(kind: .white, text: "White Tester 5d"),
            .init(kind: .other, text: "White won by resignation"),
            .init(kind: .other, text: "Fixture Cup"),
            .init(kind: .other, text: "May 1, 2009"),
        ])
    }

    @Test func onlyTheFieldsTheGameHas() throws {
        let details = try Self.details("(;PB[Kuro]PW[Shiro]WR[2k]RE[B+3.5]DT[2009-05-01,02])")
        #expect(details.lines == [
            .init(kind: .black, text: "Kuro"),
            .init(kind: .white, text: "Shiro 2k"),
            .init(kind: .other, text: "Black won by 3.5 points"),
            .init(kind: .other, text: "2009-05-01,02"),
        ])
        #expect(try Self.details("(;PB[Kuro]PW[Shiro])").lines.count == 2)
    }

    @Test func theHintComesLast() throws {
        let details = try Self.details("(;PB[Kuro]PW[Shiro]EV[Cup])", hint: SaverGame.ownGameHint)
        #expect(details.lines.last == .init(kind: .other, text: "Open SGF Tools to choose games for this screensaver."))
    }

    @Test func theBlockFitsItsWidthAndCutsLongLines() throws {
        let long = String(repeating: "Hon'inbō Shūsaku of the Honinbo house ", count: 4)
        let details = try Self.details("(;PB[\(long)]PW[Shiro]EV[Cup])")
        let maximum = SaverLayout.maximumDetailsWidth(for: Self.screen)
        let size = try #require(DetailsRenderer.size(of: details, on: Self.screen))
        #expect(size.width <= maximum)
        let widths = DetailsRenderer.lineWidths(of: details, on: Self.screen)
        #expect(widths.count == 3)
        #expect(widths[0].isTruncated)
        #expect(!widths[1].isTruncated && !widths[2].isTruncated)
        #expect(widths[0].width > widths[1].width)

        // A short block is as wide as its widest line, and grows with the screen.
        let short = try Self.details(namedGame())
        let small = try #require(DetailsRenderer.size(of: short, on: Self.screen))
        #expect(small.width < maximum)
        #expect(small.height > 5 * Self.screen.height * Look.screensaverDetailFontFraction)
        let large = try #require(DetailsRenderer.size(of: short, on: CGSize(width: 3840, height: 2160)))
        #expect(abs(large.width / small.width - 2) < 0.15, "the system font's spacing changes a little with its size")
    }

    @Test func drawsLightTextOnClear() throws {
        let details = try Self.details(namedGame())
        let size = try #require(DetailsRenderer.size(of: details, on: Self.screen))
        let image = try #require(DetailsRenderer.makeImage(of: details, on: Self.screen, scale: 2))
        #expect(image.width == Int((size.width * 2).rounded(.up)))
        #expect(image.height == Int((size.height * 2).rounded(.up)))
        let bitmap = Bitmap(image)
        #expect(bitmap.alpha(x: image.width - 1, y: image.height - 1) == 0, "clear where there is nothing")
        // Somewhere in the first line, the text is light and nearly opaque.
        var brightest = 0.0
        for x in stride(from: image.width / 4, to: image.width / 2, by: 1) {
            for y in 0 ..< image.height / 6 where bitmap.alpha(x: x, y: y) > 200 {
                brightest = max(brightest, bitmap.brightness(x: x, y: y))
            }
        }
        #expect(brightest > 0.85)
        #expect(DetailsRenderer.makeImage(of: SaverDetails(info: GameInfo(game: try game("(;)"))), on: Self.screen,
                                          scale: 2) == nil, "no lines, no image")
    }
}
