import CoreGraphics
import Foundation
import SGFKit
import SGFRendering
import Testing

@Suite("Thumbnail")
struct ThumbnailTests {
    private let size = CGSize(width: 256, height: 256)

    /// The alpha of the pixel at a column and a row counted from the top.
    private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        }
        return pixel[3]
    }

    @Test func aGameGetsItsOpeningPosition() throws {
        let thumbnail = try #require(Thumbnail(collection: collection(longGame(size: 19, moves: 80))))
        #expect(thumbnail.position.movesShown == 50)
        #expect(!thumbnail.isCollection)
        let image = try #require(thumbnail.makeImage(size: size, scale: 2))
        #expect(image.width == 512 && image.height == 512)
        #expect(alpha(image, x: 256, y: 256) == 255)
        #expect(alpha(image, x: 1, y: 1) == 255, "a square board fills the thumbnail")
    }

    @Test func aCollectionGetsTheBackdrop() throws {
        let sgf = "(;SZ[19];B[pd];W[dp])(;SZ[9];B[ee])"
        let thumbnail = try #require(Thumbnail(collection: collection(sgf, stopAfterFirstGame: true)))
        #expect(thumbnail.isCollection)
        let image = try #require(thumbnail.makeImage(size: size, scale: 1))
        // The front board sits at the top left; the stack shows below and to the right, fading.
        #expect(alpha(image, x: 2, y: 2) == 255)
        #expect(alpha(image, x: 253, y: 2) == 0)
        #expect(alpha(image, x: 253, y: 253) < 255)
        let single = try #require(Thumbnail(collection: collection("(;SZ[19];B[pd];W[dp])")))
        #expect(!single.isCollection)
    }

    @Test func aStrayPrefixIsSkipped() throws {
        let thumbnail = try #require(Thumbnail(collection: collection("&#65279;(;SZ[9];B[ee];W[cc])")))
        #expect(thumbnail.position.totalMoves == 2)
    }

    @Test func aFileWithNoGameHasNoThumbnail() {
        #expect(Thumbnail(collection: collection("")) == nil)
        #expect(Thumbnail(collection: collection("Just some notes about a game, with (parentheses).")) == nil)
    }

    @Test func aRectangularBoardIsCenteredWithTransparentSides() throws {
        let thumbnail = try #require(Thumbnail(collection: collection("(;SZ[19:9];B[ee])")))
        let image = try #require(thumbnail.makeImage(size: size, scale: 1))
        #expect(alpha(image, x: 128, y: 128) == 255)
        #expect(alpha(image, x: 128, y: 3) == 0)
    }

    @Test func contextSizeIsTheLargestSquare() {
        #expect(Thumbnail.contextSize(fitting: CGSize(width: 512, height: 400)) == CGSize(width: 400, height: 400))
        #expect(Thumbnail.contextSize(fitting: CGSize(width: 32.7, height: 64)) == CGSize(width: 32, height: 32))
        #expect(Thumbnail.contextSize(fitting: .zero) == CGSize(width: 1, height: 1))
    }

    @Test func johnVsGnu() throws {
        let thumbnail = try #require(try Thumbnail(contentsOf: Fixtures.johnVsGnu()))
        #expect(thumbnail.position.movesShown == 50)
        #expect(thumbnail.position.board.stones(of: .black).count >= 3, "the handicap stones are there")
    }

    /// Reading, parsing, and drawing johnVsGnu.sgf at Finder's largest thumbnail size (512
    /// points at 2x) should take well under a frame's worth of time on Apple Silicon.
    @Test func fastEnough() throws {
        let url = try Fixtures.johnVsGnu()
        let clock = ContinuousClock()
        var durations: [Duration] = []
        for _ in 0 ..< 20 {
            let duration = try clock.measure {
                let thumbnail = try #require(try Thumbnail(contentsOf: url))
                _ = try #require(thumbnail.makeImage(size: CGSize(width: 512, height: 512), scale: 2))
            }
            durations.append(duration)
        }
        let median = durations.sorted()[durations.count / 2]
        print("Thumbnail of johnVsGnu.sgf at 1024x1024 px: median \(median), fastest \(durations.min()!)")
        #expect(median < .milliseconds(50))
    }
}
