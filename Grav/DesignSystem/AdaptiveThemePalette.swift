import SwiftUI

/// Appearance-resolved visual tokens bridging Grav's Dark Liquid Glass palette
/// with crisp, high-contrast macOS Light Mode surfaces for Settings and popovers.
public struct GravAdaptivePalette: Sendable {
    public let colorScheme: ColorScheme

    public init(colorScheme: ColorScheme) {
        self.colorScheme = colorScheme
    }

    public var isDark: Bool {
        colorScheme == .dark
    }

    // MARK: - Substrates & Calm 3-Step Fills

    public var windowBackground: Color {
        isDark
            ? GravPalette.obsidianSurface
            : Color(red: 0xF4 / 255.0, green: 0xF6 / 255.0, blue: 0xF8 / 255.0)
    }

    public var fillSubtle: Color {
        isDark
            ? GravPalette.cardFillSubtle
            : Color.black.opacity(0.032)
    }

    public var fillBase: Color {
        isDark
            ? GravPalette.cardFillBase
            : Color.white.opacity(0.82)
    }

    public var fillElevated: Color {
        isDark
            ? GravPalette.cardFillElevated
            : Color.white.opacity(0.96)
    }

    // MARK: - 4-Step Ink Ramp

    public var inkPrimary: Color {
        isDark
            ? GravPalette.inkPrimary
            : Color(red: 0x0B / 255.0, green: 0x12 / 255.0, blue: 0x19 / 255.0).opacity(0.94)
    }

    public var inkSecondary: Color {
        isDark
            ? GravPalette.inkSecondary
            : Color(red: 0x0B / 255.0, green: 0x12 / 255.0, blue: 0x19 / 255.0).opacity(0.68)
    }

    public var inkTertiary: Color {
        isDark
            ? GravPalette.inkTertiary
            : Color(red: 0x0B / 255.0, green: 0x12 / 255.0, blue: 0x19 / 255.0).opacity(0.48)
    }

    public var inkQuaternary: Color {
        isDark
            ? GravPalette.inkQuaternary
            : Color(red: 0x0B / 255.0, green: 0x12 / 255.0, blue: 0x19 / 255.0).opacity(0.28)
    }

    // MARK: - Borders & Hairlines

    public var specularStroke: LinearGradient {
        if isDark {
            return GravPalette.specularStroke
        }
        return LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.06), location: 0.0),
                .init(color: Color.black.opacity(0.09), location: 0.55),
                .init(color: Color.black.opacity(0.13), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public var divider: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.075)
    }

    public var hoverFill: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.05)
    }

    public var pressedFill: Color {
        isDark ? Color.white.opacity(0.13) : Color.black.opacity(0.085)
    }

    // MARK: - Contrast-Calibrated Semantic Accents

    public var accentTeal: Color {
        isDark
            ? GravPalette.glacialTeal
            : Color(red: 0x0A / 255.0, green: 0x7A / 255.0, blue: 0xEB / 255.0)
    }

    public var emeraldText: Color {
        isDark
            ? GravPalette.emerald
            : Color(red: 0x0F / 255.0, green: 0x9D / 255.0, blue: 0x6E / 255.0)
    }

    public var coralText: Color {
        isDark
            ? GravPalette.coral
            : Color(red: 0xD9 / 255.0, green: 0x43 / 255.0, blue: 0x43 / 255.0)
    }

    public var fileEditText: Color {
        isDark
            ? GravPalette.fileEdit
            : Color(red: 0xC7 / 255.0, green: 0x77 / 255.0, blue: 0x00 / 255.0)
    }

    public var idleDot: Color {
        isDark ? GravPalette.idleDot : Color.black.opacity(0.24)
    }
}
