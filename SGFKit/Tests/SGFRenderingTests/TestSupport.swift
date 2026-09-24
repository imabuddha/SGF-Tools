import CoreGraphics
import Foundation
import SGFKit
import SGFRendering
import Testing

/// The pixels of an image in 8-bit sRGB, row 0 at the top.
struct Pixels {
    struct Color {
        let red: Int
        let green: Int
        let blue: Int
        let alpha: Int

        /// Relative brightness from 0 to 1, ignoring alpha.
        var brightness: Double {
            (0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)) / 255
        }

        /// The largest difference in any channel.
        func distance(to other: Color) -> Int {
            max(abs(red - other.red), abs(green - other.green), abs(blue - other.blue), abs(alpha - other.alpha))
        }
    }

    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let (width, height) = (width, height)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.bytes = bytes
    }

    /// The pixel at a column and a row counted from the top.
    subscript(x: Int, y: Int) -> Color {
        let offset = (y * width + x) * 4
        return Color(red: Int(bytes[offset]), green: Int(bytes[offset + 1]),
                     blue: Int(bytes[offset + 2]), alpha: Int(bytes[offset + 3]))
    }

    subscript(point: (x: Double, y: Double)) -> Color {
        self[Int(point.x.rounded(.down)), Int(point.y.rounded(.down))]
    }

    /// The total darkness (1 - brightness) of a square of pixels around a point.
    func darkness(around point: (x: Double, y: Double), radius: Int) -> Double {
        let cx = Int(point.x.rounded(.down))
        let cy = Int(point.y.rounded(.down))
        var total = 0.0
        for y in cy - radius ... cy + radius {
            for x in cx - radius ... cx + radius where (0 ..< width).contains(x) && (0 ..< height).contains(y) {
                total += 1 - self[x, y].brightness
            }
        }
        return total
    }
}

/// The grid lines found in an image of an empty board, from the rows and columns of pixels
/// that are mostly dark.
struct DetectedGrid {
    /// The center of each vertical line, in pixels from the left, and its width.
    let columns: [(center: Double, width: Int)]
    /// The center of each horizontal line, in pixels from the top, and its width.
    let rows: [(center: Double, width: Int)]

    init(_ pixels: Pixels, darkBelow threshold: Double = 0.5) {
        var columnCounts = [Int](repeating: 0, count: pixels.width)
        var rowCounts = [Int](repeating: 0, count: pixels.height)
        for y in 0 ..< pixels.height {
            for x in 0 ..< pixels.width where pixels[x, y].alpha > 0 && pixels[x, y].brightness < threshold {
                columnCounts[x] += 1
                rowCounts[y] += 1
            }
        }
        columns = Self.runs(in: columnCounts)
        rows = Self.runs(in: rowCounts)
    }

    /// Runs of indexes whose count is over half the largest count.
    private static func runs(in counts: [Int]) -> [(center: Double, width: Int)] {
        let limit = (counts.max() ?? 0) / 2
        var runs: [(center: Double, width: Int)] = []
        var start: Int?
        for (index, count) in counts.enumerated() + [(counts.count, 0)] {
            if count > limit, limit > 0 {
                if start == nil { start = index }
            } else if let first = start {
                runs.append((center: Double(first + index) / 2, width: index - first))
                start = nil
            }
        }
        return runs
    }

    /// Where a point's lines cross, in pixels from the top left. For the outer lines, which grow
    /// outward, this uses the inner pixel of the line.
    func center(column: Int, row: Int) -> (x: Double, y: Double) {
        func middle(_ lines: [(center: Double, width: Int)], _ index: Int) -> Double {
            let line = lines[index - 1]
            let innerWidth = Double(lines.count > 2 ? lines[1].width : 1)
            let grow = (Double(line.width) - innerWidth) / 2
            if index == 1 { return line.center + grow }
            if index == lines.count { return line.center - grow }
            return line.center
        }
        return (middle(columns, column), middle(rows, row))
    }
}

extension CGImage {
    /// The image's pixels.
    var pixels: Pixels { Pixels(self) }
}

/// A point from its SGF letters.
func pt(_ sgf: String) -> SGFPoint {
    SGFPoint(sgf: sgf)!
}

/// A board with stones at the given SGF points.
func board(_ size: BoardSize = .standard, black: [String] = [], white: [String] = []) -> Board {
    var board = Board(size: size)
    for point in black { board.place(.black, at: pt(point)) }
    for point in white { board.place(.white, at: pt(point)) }
    return board
}
