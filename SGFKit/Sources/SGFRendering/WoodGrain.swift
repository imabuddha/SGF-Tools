import CoreGraphics
import Foundation

/// A procedural wood texture for the shaded board: straight grain running from top to bottom,
/// made of fine dark lines at uneven spacing, fine fibers, and a broad variation in tone.
///
/// Everything is computed from fixed constants, so the texture is the same on every run. It is
/// made once, on first use, and shared.
enum WoodGrain {
    /// The texture's width, across the grain.
    static let width = 512

    /// The texture's height, along the grain. The grain changes slowly in this direction, so
    /// the texture is stretched to the board's height.
    static let height = 128

    /// The light and dark ends of the wood's color range (sRGB).
    static let light: (red: Double, green: Double, blue: Double) = (0.925, 0.785, 0.545)
    static let dark: (red: Double, green: Double, blue: Double) = (0.765, 0.575, 0.330)

    /// The texture. Drawing it into a square fills the board with grain.
    static let image: CGImage? = makeImage()

    /// The texture's average color, for anything drawn in the wood's color without the grain.
    static let averageColor: CGColor = {
        let mean = averageMix
        return CGColor(
            srgbRed: light.red + (dark.red - light.red) * mean,
            green: light.green + (dark.green - light.green) * mean,
            blue: light.blue + (dark.blue - light.blue) * mean,
            alpha: 1
        )
    }()

    /// How far toward `dark` the texture is on average.
    private static let averageMix: Double = {
        var total = 0.0
        for y in stride(from: 0, to: height, by: 4) {
            for x in 0 ..< width {
                total += mix(x: x, y: y)
            }
        }
        return total / Double(width * height / 4)
    }()

    private static func makeImage() -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let t = mix(x: x, y: y)
                let offset = (y * width + x) * 4
                bytes[offset] = byte(light.red + (dark.red - light.red) * t)
                bytes[offset + 1] = byte(light.green + (dark.green - light.green) * t)
                bytes[offset + 2] = byte(light.blue + (dark.blue - light.blue) * t)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// How far toward the dark color a texture pixel is, from 0 to 1.
    private static func mix(x: Int, y: Int) -> Double {
        let across = Double(x) / Double(width)
        let along = Double(y) / Double(height)

        // The grain wanders a little as it runs along the board.
        let wander = 0.010 * (noise(along * 1.7 + 3.1) - 0.5)
            + 0.004 * sin(2 * .pi * (along * 1.3 + across * 2.0 + 0.2))
        let u = across + wander

        // Dark growth lines at uneven spacing, each with its own strength, fading in and out.
        let lineCount = 46.0
        let warped = u * lineCount + 0.9 * (noise(u * 9 + 7.7) - 0.5)
        let index = warped.rounded(.down)
        let phase = warped - index
        let distance = min(phase, 1 - phase)
        let strength = 0.35 + 0.65 * hash(Int(index) &+ 101)
        let fade = 0.55 + 0.45 * noise(along * 2.3 + index * 0.37)
        let lines = strength * fade * exp(-pow(distance / 0.07, 2))

        // Fine fibers between the lines, and a slow change in tone across the board.
        let fibers = noise(u * 420 + 13) * 0.7 + noise(u * 170 + 5) * 0.3
        let tone = noise(u * 3.2 + 1.3)

        let t = 0.50 * lines + 0.22 * fibers + 0.30 * tone
        return min(1, max(0, t))
    }

    /// Smooth 1D value noise in 0-1.
    private static func noise(_ x: Double) -> Double {
        let cell = x.rounded(.down)
        let f = x - cell
        let s = f * f * (3 - 2 * f)
        let a = hash(Int(cell))
        let b = hash(Int(cell) &+ 1)
        return a + (b - a) * s
    }

    /// A deterministic pseudo-random number in 0-1 for an integer (SplitMix64).
    private static func hash(_ n: Int) -> Double {
        var z = UInt64(bitPattern: Int64(n)) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }
}
