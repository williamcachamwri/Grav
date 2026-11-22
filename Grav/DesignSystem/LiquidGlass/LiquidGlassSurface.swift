import AppKit
import SwiftUI

public enum LiquidGlassLayer: Sendable, Equatable {
    case backdrop
    case control
}

public enum LiquidGlassNativeVariant: Sendable, Equatable {
    case regular
    case clear
}

public enum LiquidGlassHighlight: Equatable, Sendable {
    case specular
    case custom(top: Double, bottom: Double)
    case none

    public var stops: (top: Color, bottom: Color)? {
        switch self {
        case .specular:
            return (LiquidGlassTokens.specularTopColor, LiquidGlassTokens.specularBottomColor)
        case let .custom(top, bottom):
            return (.white.opacity(top), .white.opacity(bottom))
        case .none:
            return nil
        }
    }
}

// MARK: - Legacy Refraction Layer

public struct LiquidGlassRefraction<S: InsettableShape>: View {
    public var shape: S
    public var layer: LiquidGlassLayer = .control

    public init(shape: S, layer: LiquidGlassLayer = .control) {
        self.shape = shape
        self.layer = layer
    }

    @ViewBuilder
    public var body: some View {
        switch layer {
        case .backdrop:
            LiquidGlassVibrancyBackdrop(material: .hudWindow, blending: .behindWindow)
                .clipShape(shape)
        case .control:
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(LiquidGlassTokens.fallbackControlSheenTop),
                        Color.white.opacity(LiquidGlassTokens.fallbackControlSheenBottom),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

// MARK: - Legacy Composite Surface

public struct LiquidGlassSurface<S: InsettableShape>: View {
    public var shape: S
    public var substrate: CGFloat = LiquidGlassTokens.baseDarkness
    public var dim: CGFloat = 0
    public var tint: CGFloat = 0
    public var highlight: LiquidGlassHighlight = .specular
    public var layer: LiquidGlassLayer = .control
    public var withRimLighting: Bool = false
    public var glassTint: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    public init(
        shape: S,
        substrate: CGFloat = LiquidGlassTokens.baseDarkness,
        dim: CGFloat = 0,
        tint: CGFloat = 0,
        highlight: LiquidGlassHighlight = .specular,
        layer: LiquidGlassLayer = .control,
        withRimLighting: Bool = false,
        glassTint: Color? = nil
    ) {
        self.shape = shape
        self.substrate = substrate
        self.dim = dim
        self.tint = tint
        self.highlight = highlight
        self.layer = layer
        self.withRimLighting = withRimLighting
        self.glassTint = glassTint
    }

    public var body: some View {
        ZStack {
            if let glassTint {
                shape.fill(glassTint)

                if let stops = highlight.stops {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [stops.top, stops.bottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: LiquidGlassTokens.specularLineWidth
                    )
                }
            } else {
                if resolvedSubstrate > 0 {
                    shape.fill(LiquidGlassTokens.substrateFill.opacity(resolvedSubstrate))
                }

                LiquidGlassRefraction(shape: shape, layer: layer)
                    .clipShape(shape)

                if dim > 0 {
                    shape.fill(LiquidGlassTokens.substrateFill.opacity(dim))
                }

                if resolvedTint > 0 {
                    shape.fill(LiquidGlassTokens.veilFill.opacity(resolvedTint))
                }

                if withRimLighting {
                    LiquidGlassRimBorder(shape: shape, isHovered: false, isEnabled: true)
                } else if let stops = highlight.stops {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [stops.top, stops.bottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: LiquidGlassTokens.specularLineWidth
                    )
                }
            }
        }
    }

    private var isDark: Bool { colorScheme == .dark }

    private var resolvedSubstrate: CGFloat {
        let base = layer == .backdrop ? LiquidGlassTokens.backdropSubstrate(substrate) : substrate
        return isDark ? base : base * 0.55
    }

    private var resolvedTint: Double {
        LiquidGlassTokens.veilOpacity(tint, isDark: isDark)
    }
}

// MARK: - View Modifiers

public extension View {
    /// Dual-path Liquid Glass surface ported 1:1 from Snapzy:
    /// Native `.glassEffect(...)` on macOS 26+, 4-layer optical composite on macOS 14–15.
    func liquidGlassSurface<S: InsettableShape>(
        shape: S,
        isVisible: Bool = true,
        substrate: CGFloat = LiquidGlassTokens.baseDarkness,
        dim: CGFloat = 0,
        tint: CGFloat = 0,
        highlight: LiquidGlassHighlight = .specular,
        layer: LiquidGlassLayer = .control,
        withRimLighting: Bool = false,
        isInteractive: Bool = false,
        glassTint: Color? = nil,
        nativeGlassTint: Color? = nil,
        nativeHighlight: LiquidGlassHighlight? = nil,
        nativeVariant: LiquidGlassNativeVariant = .regular
    ) -> some View {
        modifier(LiquidGlassSurfaceModifier(
            shape: shape,
            isVisible: isVisible,
            substrate: substrate,
            dim: dim,
            tint: tint,
            highlight: highlight,
            layer: layer,
            withRimLighting: withRimLighting,
            isInteractive: isInteractive,
            glassTint: glassTint,
            nativeGlassTint: nativeGlassTint,
            nativeHighlight: nativeHighlight,
            nativeVariant: nativeVariant
        ))
    }

    func liquidGlass<S: InsettableShape>(
        shape: S,
        substrate: CGFloat = LiquidGlassTokens.baseDarkness,
        dim: CGFloat = 0,
        tint: CGFloat = 0,
        highlight: LiquidGlassHighlight = .specular,
        layer: LiquidGlassLayer = .control,
        withRimLighting: Bool = false,
        isInteractive: Bool = false,
        glassTint: Color? = nil,
        nativeGlassTint: Color? = nil,
        nativeHighlight: LiquidGlassHighlight? = nil
    ) -> some View {
        liquidGlassSurface(
            shape: shape,
            substrate: substrate,
            dim: dim,
            tint: tint,
            highlight: highlight,
            layer: layer,
            withRimLighting: withRimLighting,
            isInteractive: isInteractive,
            glassTint: glassTint,
            nativeGlassTint: nativeGlassTint,
            nativeHighlight: nativeHighlight
        )
        .contentShape(shape)
    }
}

private struct LiquidGlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let isVisible: Bool
    let substrate: CGFloat
    let dim: CGFloat
    let tint: CGFloat
    let highlight: LiquidGlassHighlight
    let layer: LiquidGlassLayer
    let withRimLighting: Bool
    let isInteractive: Bool
    let glassTint: Color?
    let nativeGlassTint: Color?
    let nativeHighlight: LiquidGlassHighlight?
    let nativeVariant: LiquidGlassNativeVariant

    @Environment(\.liquidGlassRenderMode) private var renderMode
    @AppStorage(GravPreferenceKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

    private var usesNativeGlass: Bool {
        LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let useNative = usesNativeGlass

        if #available(macOS 26.0, *), useNative {
            content
                .glassEffect(
                    LiquidGlassNativeStyle.glass(
                        isVisible: isVisible,
                        isInteractive: isInteractive,
                        tint: nativeGlassTint ?? glassTint,
                        variant: nativeVariant
                    ),
                    in: shape
                )
                .overlay {
                    if isVisible, let stops = nativeHighlight?.stops {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [stops.top, stops.bottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: LiquidGlassTokens.specularLineWidth
                        )
                    }
                }
        } else {
            content.background {
                if isVisible {
                    LiquidGlassSurface(
                        shape: shape,
                        substrate: substrate,
                        dim: dim,
                        tint: tint,
                        highlight: highlight,
                        layer: layer,
                        withRimLighting: withRimLighting,
                        glassTint: glassTint
                    )
                }
            }
        }
    }
}

public enum LiquidGlassNativeStyle {
    @available(macOS 26.0, *)
    public static func glass(
        isVisible: Bool,
        isInteractive: Bool,
        tint: Color?,
        variant: LiquidGlassNativeVariant = .regular
    ) -> Glass {
        guard isVisible else { return .identity }
        var glass: Glass = variant == .clear ? .clear : .regular
        if let tint {
            glass = glass.tint(tint)
        }
        return isInteractive ? glass.interactive() : glass
    }
}
