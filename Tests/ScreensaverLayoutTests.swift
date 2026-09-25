import CoreGraphics
import Foundation
import Testing

@Suite("Screensaver: layout")
struct ScreensaverLayoutTests {
    /// Details of a typical size for a screen: a quarter of its shorter side wide, which is about
    /// what "Black Tester 3d" takes at the players' size, and five lines tall.
    static func typicalDetails(for screen: CGSize) -> CGSize {
        let shorter = min(screen.width, screen.height)
        return CGSize(width: shorter * 0.25, height: shorter * 0.16)
    }

    static let screens: [CGSize] = [
        CGSize(width: 1920, height: 1080), CGSize(width: 2560, height: 1440), CGSize(width: 1728, height: 1117),
        CGSize(width: 3440, height: 1440), CGSize(width: 1080, height: 1920), CGSize(width: 1024, height: 768),
        CGSize(width: 1024, height: 1024),
    ]

    @Test(arguments: screens)
    func detailsStayOnScreenAndClearOfTheBoard(screen: CGSize) throws {
        let bounds = CGRect(origin: .zero, size: screen)
        let details = Self.typicalDetails(for: screen)
        let tolerance: CGFloat = 0.001
        var sides = Set<String>()
        for seed in 0 ..< 1000 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let layout = try #require(SaverLayout(screen: screen, details: details, using: &generator))
            let m = layout.margin
            #expect(!layout.isPreview)
            #expect(layout.board.width == layout.board.height)
            #expect(bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(layout.board), "the board fits")
            let rect = try #require(layout.details, "seed \(seed)")
            #expect(rect.size == details)
            #expect(bounds.insetBy(dx: m - tolerance, dy: m - tolerance).contains(rect), "m from every edge")
            #expect(!rect.intersects(layout.board))
            let gap = max(layout.board.minX - rect.maxX, rect.minX - layout.board.maxX,
                          layout.board.minY - rect.maxY, rect.minY - layout.board.maxY)
            #expect(gap >= m - tolerance, "m from the board")
            // The board is m from the edges along the long axis, and centered across it.
            if screen.width >= screen.height {
                #expect(layout.board.minX >= m - tolerance && layout.board.maxX <= screen.width - m + tolerance)
                #expect(abs(layout.board.midY - screen.height / 2) < tolerance)
            } else {
                #expect(layout.board.minY >= m - tolerance && layout.board.maxY <= screen.height - m + tolerance)
                #expect(abs(layout.board.midX - screen.width / 2) < tolerance)
            }
            sides.insert("\(layout.side.map { "\($0)" } ?? "none")")
        }
        #expect(sides.count == 2, "\(sides)")
    }

    @Test func theBoardAndBandsOfASixteenInchMacBookPro() throws {
        let screen = CGSize(width: 1728, height: 1117)
        var generator = SeededGenerator(seed: 1)
        let layout = try #require(SaverLayout(screen: screen, details: Self.typicalDetails(for: screen), using: &generator))
        #expect(abs(layout.board.width - 960.6) < 0.1)
        #expect(abs(screen.width - layout.board.width - 767.4) < 0.1)
    }

    @Test func theBoardMovesFromGameToGame() throws {
        let screen = CGSize(width: 1920, height: 1080)
        var generator = SeededGenerator(seed: 9)
        var positions = Set<Int>()
        for _ in 0 ..< 20 {
            let layout = try #require(SaverLayout(screen: screen, details: Self.typicalDetails(for: screen), using: &generator))
            positions.insert(Int(layout.board.minX))
        }
        #expect(positions.count > 10)
    }

    @Test func aPreviewHasNoDetails() throws {
        var generator = SeededGenerator(seed: 1)
        let screen = CGSize(width: 300, height: 190)
        let layout = try #require(SaverLayout(screen: screen, details: CGSize(width: 50, height: 30), using: &generator))
        #expect(layout.isPreview)
        #expect(layout.details == nil)
        #expect(layout.board.isClose(to: CGRect(x: 64.5, y: 9.5, width: 171, height: 171)))
        #expect(SaverLayout.isPreview(CGSize(width: 1000, height: 399)))
        #expect(!SaverLayout.isPreview(CGSize(width: 1000, height: 400)))
    }

    @Test func emptyBoundsHaveNoLayout() {
        var generator = SeededGenerator(seed: 1)
        #expect(SaverLayout(screen: .zero, details: CGSize(width: 10, height: 10), using: &generator) == nil)
        #expect(SaverLayout(screen: CGSize(width: 800, height: 0), details: nil, using: &generator) == nil)
        #expect(SaverLayout(screen: CGSize(width: CGFloat.infinity, height: 800), details: nil, using: &generator) == nil)
    }

    @Test func aScreenWithNoRoomLeavesTheDetailsOut() throws {
        var generator = SeededGenerator(seed: 1)
        // Details at the widest allowed on a square screen leave a board under 60% of it.
        let screen = CGSize(width: 1024, height: 1024)
        let wide = CGSize(width: SaverLayout.maximumDetailsWidth(for: screen), height: 150)
        let layout = try #require(SaverLayout(screen: screen, details: wide, using: &generator))
        #expect(layout.details == nil)
        #expect(layout.leftOutDetails)
        #expect(abs(layout.board.width - 1024 * 0.86) < 0.001)
        #expect(abs(layout.board.midX - 512) < 0.001)
        // So do details taller than the screen.
        let tall = try #require(SaverLayout(screen: CGSize(width: 1920, height: 1080),
                                            details: CGSize(width: 200, height: 1100), using: &generator))
        #expect(tall.details == nil && tall.leftOutDetails)
    }

    @Test func aGameWithoutDetailsGetsACenteredBoard() throws {
        var generator = SeededGenerator(seed: 1)
        let layout = try #require(SaverLayout(screen: CGSize(width: 1920, height: 1080), details: nil, using: &generator))
        #expect(layout.details == nil && !layout.leftOutDetails)
        #expect(layout.board.isClose(to: CGRect(x: 495.6, y: 75.6, width: 928.8, height: 928.8)))
    }
}

extension CGRect {
    /// Whether every edge is within a thousandth of a point of another rect's.
    func isClose(to other: CGRect) -> Bool {
        [minX - other.minX, minY - other.minY, maxX - other.maxX, maxY - other.maxY].allSatisfy { abs($0) < 0.001 }
    }
}
