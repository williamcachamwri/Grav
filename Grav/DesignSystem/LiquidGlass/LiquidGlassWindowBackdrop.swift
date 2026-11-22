import SwiftUI

/// Full-window Liquid Glass backdrop ported 1:1 from Snapzy's `LiquidGlassWindowBackdrop` / `SnapzyGlassWindowBackdrop`.
/// Combines live AppKit `.hudWindow` behind-window vibrancy, directional black scrim, top-leading radial bloom,
/// 1pt top specular hairline, and 0.5pt outer perimeter stroke.
public struct LiquidGlassWindowBackdrop: View {
    public var cornerRadius: CGFloat = LiquidGlassTokens.windowRadius
    public var bloomRadius: CGFloat = 620

    public init(
        cornerRadius: CGFloat = LiquidGlassTokens.windowRadius,
        bloomRadius: CGFloat = 620
    ) {
        self.cornerRadius = cornerRadius
        self.bloomRadius = bloomRadius
    }

    public var body: some View {
        ZStack {
            LiquidGlassVibrancyBackdrop(material: .hudWindow, blending: .behindWindow)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.46),
                    Color.black.opacity(0.38),
                    Color.black.opacity(0.44),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color.white.opacity(0.06), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: bloomRadius
            )
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.white.opacity(0.02), .white.opacity(0.34), .white.opacity(0.02)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: LiquidGlassTokens.specularLineWidth)
        )
    }
}
