import AppKit
import SwiftUI

// MARK: - Capabilities

public enum LiquidGlassRenderMode: Sendable, Equatable {
    case system
    case native
    case legacy
}

private struct LiquidGlassRenderModeKey: EnvironmentKey {
    static let defaultValue: LiquidGlassRenderMode = .system
}

public extension EnvironmentValues {
    var liquidGlassRenderMode: LiquidGlassRenderMode {
        get { self[LiquidGlassRenderModeKey.self] }
        set { self[LiquidGlassRenderModeKey.self] = newValue }
    }
}

public enum LiquidGlassCapabilities {
    /// Dynamic runtime override used by tests.
    @MainActor public static var runtimeLegacyOverride: Bool? = nil

    /// Whether the host operating system supports Apple's native Liquid Glass APIs.
    public static var isSystemSupported: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    /// Whether the user enabled Liquid Glass in Settings (default true).
    public static var isUserPreferenceEnabled: Bool {
        UserDefaults.standard.object(forKey: GravPreferenceKeys.useLiquidGlass) as? Bool ?? true
    }

    #if DEBUG
    public static let argumentForcesLegacy: Bool =
        ProcessInfo.processInfo.arguments.contains("-GravForceLegacyGlass")
        || ProcessInfo.processInfo.environment["GRAV_FORCE_LEGACY_GLASS"] == "1"
    #endif

    @MainActor
    public static var forcesLegacyGlass: Bool {
        if let runtime = runtimeLegacyOverride {
            return runtime
        }
        if !isUserPreferenceEnabled {
            return true
        }
        #if DEBUG
        return argumentForcesLegacy
        #else
        return false
        #endif
    }

    @MainActor
    public static var hasNativeLiquidGlass: Bool {
        isSystemSupported && !forcesLegacyGlass
    }

    @MainActor
    public static func usesNativeGlass(for mode: LiquidGlassRenderMode, userEnabled: Bool) -> Bool {
        switch mode {
        case .system:
            guard userEnabled, isSystemSupported else { return false }
            return !developerForcedLegacy
        case .native:
            if #available(macOS 26.0, *) {
                return true
            }
            return false
        case .legacy:
            return false
        }
    }

    @MainActor
    public static func usesNativeGlass(for mode: LiquidGlassRenderMode) -> Bool {
        usesNativeGlass(for: mode, userEnabled: isUserPreferenceEnabled)
    }

    @MainActor
    private static var developerForcedLegacy: Bool {
        if let runtime = runtimeLegacyOverride {
            return runtime
        }
        #if DEBUG
        return argumentForcesLegacy
        #else
        return false
        #endif
    }
}

// MARK: - Tokens (Exact Snapzy Parity)

public enum LiquidGlassTokens {
    // Base dark substrate (Dark Aqua)
    public static let baseDarkness: CGFloat = 0.60
    public static let fallbackSubstrateScale: CGFloat = 0.40

    // Specular hairline physics
    public static let specularLineWidth: CGFloat = 0.50
    public static let specularTopColor: Color = .white.opacity(0.22)
    public static let specularBottomColor: Color = .white.opacity(0.06)

    // Control substrate levels
    public static let controlSubstrateResting: CGFloat = 0.45
    public static let controlSubstrateHover: CGFloat = 0.60
    public static let controlSubstratePressed: CGFloat = 0.72

    // Control stroke levels
    public static let controlStrokeResting: CGFloat = 0.12
    public static let controlStrokeHover: CGFloat = 0.26

    // Fallback control gradient sheen
    public static let fallbackControlSheenTop: Double = 0.00
    public static let fallbackControlSheenBottom: Double = 0.00

    // Leading & Trailing edge lighting
    public static let rimLeadingResting: Double = 0.34
    public static let rimLeadingHover: Double = 0.56
    public static let rimTrailingResting: Double = 0.22
    public static let rimTrailingHover: Double = 0.42

    // Lens caustics / corner glare blooms
    public static let glareLeadingResting: Double = 0.18
    public static let glareLeadingHover: Double = 0.32
    public static let glareTrailingResting: Double = 0.12
    public static let glareTrailingHover: Double = 0.24

    // Radii aliased onto RadiusTokens
    public static let controlRadius = Radius.controlM
    public static let cardRadius = Radius.card
    public static let surfaceRadius = Radius.panel
    public static let windowRadius = Radius.window

    // Spring physics
    public static let hoverSpring: Animation = .spring(response: 0.28, dampingFraction: 0.75)
    public static let pressSpring: Animation = .spring(response: 0.18, dampingFraction: 0.80)
    public static let settleSpring: Animation = .spring(response: 0.24, dampingFraction: 0.82)

    // Adaptive Text Ink
    public static let inkPrimary: Color = adaptiveInk(dark: 1.00, light: 0.92)
    public static let inkBody: Color = adaptiveInk(dark: 0.72, light: 0.68)
    public static let inkMuted: Color = adaptiveInk(dark: 0.46, light: 0.50)
    public static let inkFaint: Color = adaptiveInk(dark: 0.24, light: 0.28)
    public static let inkOverlay: Color = .white

    public static var inkOnAccent: Color { ink(onTint: .accentColor) }

    public static func ink(onTint tint: Color?, otherwise fallback: Color = inkPrimary) -> Color {
        guard let tint else { return fallback }
        return resolveTintLuminanceInk(tint: tint)
    }

    public static func ink(
        onTint tint: Color?,
        renderMode: LiquidGlassRenderMode,
        otherwise fallback: Color = inkPrimary
    ) -> Color {
        _ = renderMode
        guard let tint else { return fallback }
        return resolveTintLuminanceInk(tint: tint)
    }

    private static func resolveTintLuminanceInk(tint: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            var luminance: CGFloat = 0
            appearance.performAsCurrentDrawingAppearance {
                luminance = relativeLuminance(of: tint)
            }
            return luminance > 0.55 ? NSColor.black.withAlphaComponent(0.88) : .white
        })
    }

    private static func relativeLuminance(of color: Color) -> CGFloat {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return 0 }

        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * channel(rgb.redComponent)
            + 0.7152 * channel(rgb.greenComponent)
            + 0.0722 * channel(rgb.blueComponent)
    }

    public static let substrateFill: Color = adaptiveNeutral(dark: .black, light: .white)
    public static let veilFill: Color = adaptiveNeutral(dark: .white, light: .black)

    @MainActor
    public static func backdropSubstrate(_ base: CGFloat) -> CGFloat {
        LiquidGlassCapabilities.hasNativeLiquidGlass ? base : base * fallbackSubstrateScale
    }

    public static func veilOpacity(_ base: Double, isDark: Bool) -> Double {
        isDark ? base : base * 0.55
    }

    public static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func adaptiveInk(dark: CGFloat, light: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            isDark(appearance)
                ? NSColor.white.withAlphaComponent(dark)
                : NSColor.black.withAlphaComponent(light)
        })
    }

    private static func adaptiveNeutral(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            isDark(appearance) ? dark : light
        })
    }
}
