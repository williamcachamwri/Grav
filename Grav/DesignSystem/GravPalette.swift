import SwiftUI

/// Grav Aerospace Obsidian × Glacial Teal-Cyan visual palette.
/// Strictly adheres to high-precision flight-telemetry tones with zero neon or AI-slop hues.
public enum GravPalette {
    // MARK: - Substrates

    /// Pure Hardware Obsidian void backdrop (`#05080C`).
    public static let obsidianVoid = Color(red: 0x05 / 255.0, green: 0x08 / 255.0, blue: 0x0C / 255.0)

    /// Elevated obsidian panel surface (`#0A0F15`).
    public static let obsidianSurface = Color(red: 0x0A / 255.0, green: 0x0F / 255.0, blue: 0x15 / 255.0)

    /// Deep hardware bezel matte black for NotchKit surface fusion.
    public static let notchBlack = Color.black

    // MARK: - Brand Accents

    /// Primary Glacial Aerospace Teal (`#14B8A6`).
    public static let glacialTeal = Color(red: 0x14 / 255.0, green: 0xB8 / 255.0, blue: 0xA6 / 255.0)

    /// Secondary Aerospace Cyan (`#38BDF8`).
    public static let glacialCyan = Color(red: 0x38 / 255.0, green: 0xBD / 255.0, blue: 0xF8 / 255.0)

    /// Luminous Titanium White (`#F8FAFC`).
    public static let titaniumWhite = Color(red: 0xF8 / 255.0, green: 0xFA / 255.0, blue: 0xFC / 255.0)

    /// Brand directional gradient from Glacial Teal to Aerospace Cyan.
    public static let brandAccentGradient = LinearGradient(
        colors: [glacialTeal, glacialCyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Semantic Telemetry Accents

    /// Thinking / Active Reasoning (`#2DD4BF`).
    public static let thinking = Color(red: 0x2D / 255.0, green: 0xD4 / 255.0, blue: 0xBF / 255.0)

    /// File Edit / Create (`#F59E0B`).
    public static let fileEdit = Color(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0)

    /// Added lines & command success exit 0 (`#34D399`).
    public static let emerald = Color(red: 0x34 / 255.0, green: 0xD3 / 255.0, blue: 0x99 / 255.0)

    /// Removed lines, file delete, destructive shell, & non-zero command exit (`#F87171`).
    public static let coral = Color(red: 0xF8 / 255.0, green: 0x71 / 255.0, blue: 0x71 / 255.0)

    /// Running command neutral luminous white pulse.
    public static let commandRunning = Color(red: 0xF8 / 255.0, green: 0xFA / 255.0, blue: 0xFC / 255.0)

    /// Idle muted indicator tone.
    public static let idleDot = Color.white.opacity(0.32)

    // MARK: - 4-Step White Ink Ramp (Dark Liquid Glass)

    public static let inkPrimary = Color.white.opacity(1.0)
    public static let inkSecondary = Color.white.opacity(0.80)
    public static let inkTertiary = Color.white.opacity(0.58)
    public static let inkQuaternary = Color.white.opacity(0.36)

    // MARK: - 3-Step Calm Dark Card Fills

    public static let cardFillSubtle = Color.white.opacity(0.045)
    public static let cardFillBase = Color.white.opacity(0.075)
    public static let cardFillElevated = Color.white.opacity(0.105)

    // MARK: - Top-Lit Specular Hairlines

    public static let hairlineTop = Color.white.opacity(0.22)
    public static let hairlineMid = Color.white.opacity(0.09)
    public static let hairlineBottom = Color.white.opacity(0.03)

    public static let specularStroke = LinearGradient(
        stops: [
            .init(color: hairlineTop, location: 0.0),
            .init(color: hairlineMid, location: 0.45),
            .init(color: hairlineBottom, location: 1.0),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
