import CoreGraphics
import SwiftUI

/// Subtle procedural photographic film grain overlay backed by a single statically
/// cached tile `CGImage` so rendering incurs zero per-frame CPU overhead.
public struct FilmGrainOverlay: View {
    public var opacity: Double

    public init(opacity: Double = 0.035) {
        self.opacity = opacity
    }

    public var body: some View {
        if let tile = FilmGrainTileCache.tileImage {
            Image(decorative: tile, scale: 1.0)
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .blendMode(.overlay)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Thread-safe one-time procedural monochrome grain tile generator.
private enum FilmGrainTileCache {
    static let tileImage: CGImage? = generateTile(dimension: 192)

    private static func generateTile(dimension: Int) -> CGImage? {
        let pixelCount = dimension * dimension
        var bytes = [UInt8](repeating: 0, count: pixelCount * 4)

        // Deterministic splitmix64-inspired PRNG for fine, organic photographic luma distribution
        var state: UInt64 = 0x5EED_6A17_9C2F_1043
        for index in 0..<pixelCount {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)

            // Triangular distribution centered near mid-gray (128) for natural film grain under .overlay
            let u1 = Int(z & 0xFF)
            let u2 = Int((z >> 8) & 0xFF)
            let luma = UInt8((u1 + u2) / 2)

            let offset = index * 4
            bytes[offset] = luma
            bytes[offset + 1] = luma
            bytes[offset + 2] = luma
            bytes[offset + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }

        return CGImage(
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: dimension * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
