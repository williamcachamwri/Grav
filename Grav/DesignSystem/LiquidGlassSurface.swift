import SwiftUI

/// Three-step calm fill hierarchy for Grav's Liquid Glass containers.
public enum LiquidGlassElevation: Sendable, Equatable, Hashable {
    /// Quiet recessed surface (`cardFillSubtle` in dark mode).
    case subtle
    /// Standard card or row container (`cardFillBase` in dark mode).
    case base
    /// Active selection, hover pill, or floating control bar (`cardFillElevated` in dark mode).
    case elevated

    public var darkFill: Color {
        switch self {
        case .subtle: return GravPalette.cardFillSubtle
        case .base: return GravPalette.cardFillBase
        case .elevated: return GravPalette.cardFillElevated
        }
    }

    public func fill(for palette: GravAdaptivePalette) -> Color {
        switch self {
        case .subtle: return palette.fillSubtle
        case .base: return palette.fillBase
        case .elevated: return palette.fillElevated
        }
    }
}

/// Standalone Liquid Glass background shape with continuous corner geometry
/// and a crisp `0.5pt` top-lit specular hairline border.
public struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public var elevation: LiquidGlassElevation
    public var radius: CGFloat
    public var adaptive: Bool
    public var includeBorder: Bool
    public var borderWidth: CGFloat

    public init(
        elevation: LiquidGlassElevation = .base,
        radius: CGFloat = GravRadius.card,
        adaptive: Bool = false,
        includeBorder: Bool = true,
        borderWidth: CGFloat = 0.5
    ) {
        self.elevation = elevation
        self.radius = radius
        self.adaptive = adaptive
        self.includeBorder = includeBorder
        self.borderWidth = borderWidth
    }

    public var body: some View {
        let palette = GravAdaptivePalette(colorScheme: adaptive ? colorScheme : .dark)
        let shape = RoundedRectangle.grav(radius)

        ZStack {
            shape.fill(adaptive ? elevation.fill(for: palette) : elevation.darkFill)

            if adaptive, !palette.isDark, elevation != .subtle {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
        }
        .overlay {
            if includeBorder {
                shape.strokeBorder(
                    adaptive ? palette.specularStroke : GravPalette.specularStroke,
                    lineWidth: borderWidth
                )
            }
        }
        .shadow(
            color: adaptive && !palette.isDark && elevation != .subtle
                ? Color.black.opacity(0.045)
                : .clear,
            radius: elevation == .elevated ? 6 : 2,
            x: 0,
            y: elevation == .elevated ? 2 : 1
        )
    }
}

/// Container modifier applying Grav's Liquid Glass fill, continuous corner clipping,
/// and `0.5pt` top-lit specular rim overlay.
public struct LiquidGlassSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public var elevation: LiquidGlassElevation
    public var radius: CGFloat
    public var adaptive: Bool
    public var includeBorder: Bool

    public init(
        elevation: LiquidGlassElevation = .base,
        radius: CGFloat = GravRadius.card,
        adaptive: Bool = false,
        includeBorder: Bool = true
    ) {
        self.elevation = elevation
        self.radius = radius
        self.adaptive = adaptive
        self.includeBorder = includeBorder
    }

    public func body(content: Content) -> some View {
        let palette = GravAdaptivePalette(colorScheme: adaptive ? colorScheme : .dark)
        let shape = RoundedRectangle.grav(radius)

        content
            .background(
                LiquidGlassBackground(
                    elevation: elevation,
                    radius: radius,
                    adaptive: adaptive,
                    includeBorder: false
                )
            )
            .clipShape(shape)
            .overlay {
                if includeBorder {
                    shape.strokeBorder(
                        adaptive ? palette.specularStroke : GravPalette.specularStroke,
                        lineWidth: 0.5
                    )
                }
            }
    }
}

public extension View {
    /// Applies Grav's Liquid Glass surface container with continuous corner curves
    /// and a `0.5pt` top-lit specular border.
    func liquidGlassSurface(
        elevation: LiquidGlassElevation = .base,
        radius: CGFloat = GravRadius.card,
        adaptive: Bool = false,
        includeBorder: Bool = true
    ) -> some View {
        modifier(
            LiquidGlassSurfaceModifier(
                elevation: elevation,
                radius: radius,
                adaptive: adaptive,
                includeBorder: includeBorder
            )
        )
    }
}
