import AppKit
import Foundation
import SGFKit
import SwiftUI
import Testing

/// Renders the preview's SwiftUI view to images with `ImageRenderer`, in light and dark mode.
///
/// When the environment variable `SGF_PREVIEW_SAMPLES` names a directory (with `xcodebuild test`,
/// set `TEST_RUNNER_SGF_PREVIEW_SAMPLES`), the images are also written there as PNGs.
@Suite("Preview rendering")
@MainActor
struct PreviewRenderingTests {
    static let directory = ProcessInfo.processInfo.environment["SGF_PREVIEW_SAMPLES"]

    /// Renders a preview at the size Quick Look is asked for (or `size`), on a window-like
    /// background.
    private func render(_ preview: GamePreview, dark: Bool, size: CGSize = Look.previewSize) throws -> CGImage {
        let background = dark ? Color(white: 0.17) : Color(white: 0.96)
        let view = GamePreviewView(preview: preview)
            .frame(width: size.width, height: size.height)
            .background(background)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        var image: CGImage?
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            image = renderer.cgImage
        }
        return try #require(image)
    }

    private func write(_ image: CGImage, name: String) throws {
        guard let directory = Self.directory else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writePNG(image, to: folder.appendingPathComponent("\(name).png"))
    }

    /// The average brightness of the pixels in a rect of the image, from 0 to 1.
    private func brightness(of image: CGImage, in rect: CGRect) -> Double {
        Bitmap(image, rect: rect).average { ($0[0] + $0[1] + $0[2]) / 765 }
    }

    /// How warm a rect of the image is: the average of red minus blue, from -1 to 1. The wood of
    /// the board is clearly warm; the gray backgrounds and the text are not.
    private func warmth(of image: CGImage, in rect: CGRect) -> Double {
        Bitmap(image, rect: rect).average { ($0[0] - $0[2]) / 255 }
    }

    @Test(arguments: [false, true])
    func johnVsGnu(dark: Bool) throws {
        let preview = try #require(try GamePreview(contentsOf: Fixtures.johnVsGnu()))
        #expect(preview.summary.result == "Black won by 17.5 points")
        // The game ends with two passes, which count as moves, as in the caption.
        #expect(preview.summary.fields.last == .init(label: "Moves", value: "234"))
        #expect(preview.position.totalMoves == 234)
        let image = try render(preview, dark: dark)
        #expect(image.width == Int(Look.previewSize.width * 2))
        #expect(image.height == Int(Look.previewSize.height * 2))
        // The info column is lighter in light mode and darker in dark mode; the board is wood
        // either way.
        let info = brightness(of: image, in: CGRect(x: 1300, y: 300, width: 400, height: 500))
        let board = brightness(of: image, in: CGRect(x: 300, y: 300, width: 200, height: 200))
        #expect(dark ? info < 0.35 : info > 0.8)
        #expect(board > 0.4)
        try write(image, name: "preview-johnVsGnu-\(dark ? "dark" : "light")")
    }

    @Test(arguments: [false, true])
    func fullInfoAndCollection(dark: Bool) throws {
        let sgf = Fixtures.fullInfo + "(;GM[1]SZ[9];B[ee])"
        let preview = try #require(GamePreview(collection: collection(sgf)))
        #expect(preview.summary.fields.last?.value == "2")
        let image = try render(preview, dark: dark)
        try write(image, name: "preview-fixture-collection-\(dark ? "dark" : "light")")
    }

    @Test func aSmallBoardWithFewFields() throws {
        let preview = try #require(GamePreview(collection: collection(longGame(size: 9, moves: 30))))
        #expect(preview.position.movesShown == 20)
        let image = try render(preview, dark: false)
        try write(image, name: "preview-9x9-light")
    }

    /// `ImageRenderer` leaves a scroll view's content out, so this only checks that a long
    /// comment doesn't grow the preview; the scrolling itself shows only in Quick Look.
    @Test func aLongCommentScrolls() throws {
        let comment = (1 ... 80).map { "Line \($0) of a long game comment." }.joined(separator: "\n")
        let preview = try #require(GamePreview(collection: collection("(;PB[B]PW[W]RE[B+R]GC[\(comment)];B[pd])")))
        let image = try render(preview, dark: true)
        #expect(image.height == Int(Look.previewSize.height * 2), "the comment doesn't grow the preview")
        try write(image, name: "preview-long-comment-dark")
    }

    /// The app's window, which the tests can't open, drawn the same way.
    @Test(arguments: [false, true])
    func appWindow(dark: Bool) throws {
        let background = dark ? Color(white: 0.17) : Color(white: 0.93)
        let view = ContentView(version: "2.0.0 (1)")
            .background(background)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        var image: CGImage?
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            image = renderer.cgImage
        }
        let window = try #require(image)
        #expect(window.width == 1040)
        try write(window, name: "app-window-\(dark ? "dark" : "light")")
    }

    /// Finder's Get Info window gives the preview a narrow, tall space (about 272 by 360 points).
    /// There the board goes above the information instead of being squeezed beside it (John,
    /// 2026-09-25: the board was a few points wide and the caption ran down one letter a line).
    @Test(arguments: [false, true])
    func aNarrowSpaceStacksTheBoardAboveTheInformation(dark: Bool) throws {
        let preview = try #require(try GamePreview(contentsOf: Fixtures.johnVsGnu()))
        let size = CGSize(width: 272, height: 360)
        let image = try render(preview, dark: dark, size: size)
        // At scale 2: the board fills the width under the 20-point padding, from the top.
        #expect(warmth(of: image, in: CGRect(x: 120, y: 80, width: 280, height: 160)) > 0.15,
                "a wide board at the top")
        // Nothing beside the board: its right-hand part is wood too, not the information.
        #expect(warmth(of: image, in: CGRect(x: 380, y: 100, width: 30, height: 120)) > 0.15)
        // The information below the board, on the plain background.
        #expect(warmth(of: image, in: CGRect(x: 60, y: 560, width: 400, height: 120)) < 0.05)
        try write(image, name: "preview-narrow-johnVsGnu-\(dark ? "dark" : "light")")
    }

    @Test func aFileWithNoGameHasNoPreview() {
        #expect(GamePreview(collection: collection("No game here.")) == nil)
    }

    /// Of a file over the limit, only the first game is read, so the preview can't count them.
    @Test func aLargeFileIsReadOnlyToItsFirstGame() throws {
        let sgf = "(;GM[1]SZ[9]PB[First];B[ee])\n(;GM[1]SZ[9]PB[Second])\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sgf")
        try Data(sgf.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let whole = try #require(try GamePreview(contentsOf: url))
        #expect(whole.summary.fields.last == .init(label: "Games", value: "2"))
        let large = try #require(try GamePreview(contentsOf: url, wholeFileLimit: sgf.utf8.count - 1))
        #expect(large.summary.fields.last == .init(label: "Games", value: "Several"))
        #expect(large.summary.black?.name == "First")
        #expect(large.position.movesShown == 1)
    }
}
